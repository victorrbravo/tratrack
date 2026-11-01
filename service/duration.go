//go:build ignore

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const apiBaseURL = "https://api.meta.ai/v1"

type Response struct {
	Output []struct {
		Type    string `json:"type"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	} `json:"output"`
}

type Place struct {
	ID           int      `json:"id"`
	Name         string   `json:"name"`
	StartSeconds float64  `json:"start_seconds"`
	EndSeconds   float64  `json:"end_seconds"`
	Location     string   `json:"location,omitempty"`
	Tips         []string `json:"tips,omitempty"`
	Spent        int      `json:"spent"`
}

// UnmarshalJSON also accepts "start"/"end" as aliases for
// "start_seconds"/"end_seconds"; output always uses the canonical names.
func (p *Place) UnmarshalJSON(data []byte) error {
	type Alias Place
	aux := &struct {
		*Alias
		Start *float64 `json:"start"`
		End   *float64 `json:"end"`
	}{Alias: (*Alias)(p)}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	if p.StartSeconds == 0 && aux.Start != nil {
		p.StartSeconds = *aux.Start
	}
	if p.EndSeconds == 0 && aux.End != nil {
		p.EndSeconds = *aux.End
	}
	return nil
}

type VideoAnalysis struct {
	Name    string  `json:"name"`
	Summary string  `json:"summary"`
	Places  []Place `json:"places"`
}

type spentResponse struct {
	Spent json.RawMessage `json:"spent"`
}

var numberRe = regexp.MustCompile(`\d+(?:\.\d+)?`)

func main() {
	apiKey := os.Getenv("MODEL_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set MODEL_API_KEY")
		os.Exit(1)
	}

	// Usage:
	//   go run duration.go <file_id> output.json
	//   go run duration.go <file_id> output.json output_spent.json
	if len(os.Args) < 3 || len(os.Args) > 4 {
		fmt.Fprintln(os.Stderr, "Usage: go run duration.go <file_id> <input.json> [output.json]")
		os.Exit(1)
	}
	fileID := strings.TrimSpace(os.Args[1])
	if fileID == "" {
		fmt.Fprintln(os.Stderr, "Usage: go run duration.go <file_id> <input.json> [output.json]")
		os.Exit(1)
	}
	inputPath := os.Args[2]
	outputPath := ""
	if len(os.Args) > 3 {
		outputPath = os.Args[3]
	} else {
		ext := filepath.Ext(inputPath)
		base := strings.TrimSuffix(inputPath, ext)
		if ext == "" {
			ext = ".json"
		}
		outputPath = base + "_spent" + ext
	}

	data, err := os.ReadFile(inputPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reading input: %v\n", err)
		os.Exit(1)
	}
	var analysis VideoAnalysis
	if err := json.Unmarshal(data, &analysis); err != nil {
		fmt.Fprintf(os.Stderr, "invalid input JSON: %v\n", err)
		os.Exit(1)
	}
	if analysis.Places == nil {
		analysis.Places = []Place{}
	}

	for i := range analysis.Places {
		place := &analysis.Places[i]
		fmt.Fprintf(os.Stderr, "[%d/%d] %s...\n", i+1, len(analysis.Places), place.Name)

		spent, err := askSpent(apiKey, fileID, analysis, *place)
		if err != nil {
			fmt.Fprintf(os.Stderr, "place %q: %v\n", place.Name, err)
			os.Exit(1)
		}
		place.Spent = spent
	}

	out, err := json.MarshalIndent(analysis, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	out = append(out, '\n')
	if err := os.WriteFile(outputPath, out, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "writing output: %v\n", err)
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "Wrote %s (%d places)\n", outputPath, len(analysis.Places))
}

// askSpent calls Muse once for a single place, consulting the video
// file identified by fileID, asking how much time a person spends on
// average visiting it.
func askSpent(apiKey, fileID string, analysis VideoAnalysis, place Place) (int, error) {
	prompt := fmt.Sprintf(`The attached video shows this place. How much average time does a person spend visiting this place?

Place: %s`, place.Name)
	if place.Location != "" {
		prompt += fmt.Sprintf("\nLocation (latitude,longitude): %s", place.Location)
	}
	if analysis.Name != "" || analysis.Summary != "" {
		prompt += fmt.Sprintf("\nContext of the place: %s. %s", analysis.Name, analysis.Summary)
	}
	prompt += `

Consider a typical visit to this place (not the minimum possible, and not an entire day unless the place normally takes a full day, e.g. a theme park).

Return ONLY a valid JSON object, with no markdown fences and no extra text, in exactly this format:
{"spent":120}

Rules:
- "spent" must be an integer number expressing the average time spent in MINUTES, e.g. 45, 120 or 480.
- No units, no ranges, no decimals, no extra text.
- If you cannot estimate this place, return {"spent":0}.`

	payload := map[string]any{
		"model": "muse-spark-1.3",
		"input": []any{
			map[string]any{
				"type": "message",
				"role": "user",
				"content": []any{
					map[string]any{
						"type": "input_text",
						"text": prompt,
					},
					map[string]any{
						"type":    "input_file",
						"file_id": fileID,
					},
				},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}

	req, err := http.NewRequest(http.MethodPost, apiBaseURL+"/responses", bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("calling API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return 0, fmt.Errorf("API error (%s): %s", resp.Status, respBody)
	}

	var result Response
	if err := json.Unmarshal(respBody, &result); err != nil {
		return 0, fmt.Errorf("invalid API response: %s", respBody)
	}

	var texts []string
	for _, item := range result.Output {
		for _, content := range item.Content {
			if content.Type == "output_text" {
				texts = append(texts, content.Text)
			}
		}
	}
	if len(texts) == 0 {
		return 0, fmt.Errorf("empty API response: %s", respBody)
	}

	return parseSpent(strings.Join(texts, "\n"))
}

func parseSpent(text string) (int, error) {
	cleaned := strings.TrimSpace(text)
	cleaned = strings.TrimPrefix(cleaned, "```json")
	cleaned = strings.TrimPrefix(cleaned, "```")
	cleaned = strings.TrimSuffix(cleaned, "```")
	cleaned = strings.TrimSpace(cleaned)
	if start, end := strings.Index(cleaned, "{"), strings.LastIndex(cleaned, "}"); start >= 0 && end > start {
		cleaned = cleaned[start : end+1]
	}

	var parsed spentResponse
	if err := json.Unmarshal([]byte(cleaned), &parsed); err != nil {
		return 0, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}
	return normalizeSpent(parsed.Spent), nil
}

// normalizeSpent converts a model value such as 120, "120", "120 minutes"
// or "2 hours" into an integer number of minutes. A range is averaged.
// Values outside (0, 1440] minutes become 0 (unknown).
func normalizeSpent(raw json.RawMessage) int {
	if len(raw) == 0 {
		return 0
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		var n float64
		if err := json.Unmarshal(raw, &n); err != nil {
			return 0
		}
		s = strconv.FormatFloat(n, 'f', -1, 64)
	}

	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return 0
	}
	isHours := strings.Contains(s, "hour") || strings.Contains(s, "hr")
	nums := numberRe.FindAllString(s, -1)
	if len(nums) == 0 {
		return 0
	}

	var total float64
	for _, num := range nums {
		v, err := strconv.ParseFloat(num, 64)
		if err != nil {
			return 0
		}
		total += v
	}
	minutes := total / float64(len(nums))
	if isHours {
		minutes *= 60
	}
	rounded := int(math.Round(minutes))
	if rounded <= 0 || rounded > 1440 {
		return 0
	}
	return rounded
}
