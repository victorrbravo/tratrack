//go:build ignore

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
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
	Tips         []string `json:"tips"`
	Tags         []string `json:"tags"`
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

type tipsResponse struct {
	Tips []string `json:"tips"`
	Tags []string `json:"tags"`
}

const maxTags = 7

func main() {
	apiKey := os.Getenv("MODEL_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set MODEL_API_KEY")
		os.Exit(1)
	}

	// Usage:
	//   go run tips.go <file_id>
	//   go run tips.go <file_id> output.json
	//   go run tips.go <file_id> output.json output_tips.json
	if len(os.Args) < 2 || strings.TrimSpace(os.Args[1]) == "" || len(os.Args) > 4 {
		fmt.Fprintln(os.Stderr, "Usage: go run tips.go <file_id> [input.json] [output.json]")
		os.Exit(1)
	}
	fileID := strings.TrimSpace(os.Args[1])
	inputPath := "output.json"
	if len(os.Args) > 2 {
		inputPath = os.Args[2]
	}
	outputPath := ""
	if len(os.Args) > 3 {
		outputPath = os.Args[3]
	} else {
		ext := filepath.Ext(inputPath)
		base := strings.TrimSuffix(inputPath, ext)
		if ext == "" {
			ext = ".json"
		}
		outputPath = base + "_tips" + ext
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
		if place.Tips == nil {
			place.Tips = []string{}
		}
		if place.Tags == nil {
			place.Tags = []string{}
		}
		fmt.Fprintf(os.Stderr, "[%d/%d] %s (%s-%s)...\n",
			i+1, len(analysis.Places), place.Name,
			formatSeconds(place.StartSeconds), formatSeconds(place.EndSeconds))

		tips, tags, err := askTips(apiKey, fileID, *place)
		if err != nil {
			fmt.Fprintf(os.Stderr, "place %q: %v\n", place.Name, err)
			os.Exit(1)
		}
		place.Tips = tips
		place.Tags = tags
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

func formatSeconds(s float64) string {
	total := int(s)
	return fmt.Sprintf("%d:%02d", total/60, total%60)
}

// askTips asks Muse for the important information and tags about one
// place, using only the section of the video defined by the place's
// time range.
func askTips(apiKey, fileID string, place Place) (tips, tags []string, err error) {
	prompt := fmt.Sprintf(`Consider ONLY the section of this video from second %v to second %v (from %s to %s). Ignore everything outside that time range.

That section is about: %s

Extract every important piece of information ("tips") about this place that is said, shown, or written in that section: practical advice, what to do or see there, highlights, recommendations, warnings, prices, schedules, or best times to visit.

Also generate "tags" associated with this place, based on that section: keywords describing its type, features, atmosphere, or activities (e.g. museum, landmark, historic, art, views, food, family).

Return ONLY a valid JSON object, with no markdown fences and no extra text, in exactly this format:
{"tips":["<tip>","<tip>"],"tags":["<tag>","<tag>"]}

Rules:
- One fact per tip, as a short and concise string, in the order it appears in the section.
- Each tag must be a single lowercase word, and there must be a maximum of %d tags.
- Only include information actually present in that section of the video. Do not invent information and do not use information from outside the time range.
- Do not repeat tips or tags.
- If the section contains no important information about the place, return {"tips":[],"tags":[]}.`,
		place.StartSeconds, place.EndSeconds,
		formatSeconds(place.StartSeconds), formatSeconds(place.EndSeconds),
		place.Name, maxTags)

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
		return nil, nil, err
	}

	req, err := http.NewRequest(http.MethodPost, apiBaseURL+"/responses", bytes.NewReader(body))
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("calling API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, nil, fmt.Errorf("API error (%s): %s", resp.Status, respBody)
	}

	var result Response
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, nil, fmt.Errorf("invalid API response: %s", respBody)
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
		return nil, nil, fmt.Errorf("empty API response: %s", respBody)
	}

	return parseTips(strings.Join(texts, "\n"))
}

func parseTips(text string) (tips, tags []string, err error) {
	cleaned := strings.TrimSpace(text)
	cleaned = strings.TrimPrefix(cleaned, "```json")
	cleaned = strings.TrimPrefix(cleaned, "```")
	cleaned = strings.TrimSuffix(cleaned, "```")
	cleaned = strings.TrimSpace(cleaned)
	if start, end := strings.Index(cleaned, "{"), strings.LastIndex(cleaned, "}"); start >= 0 && end > start {
		cleaned = cleaned[start : end+1]
	}

	var parsed tipsResponse
	if err := json.Unmarshal([]byte(cleaned), &parsed); err != nil {
		return nil, nil, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	tips = make([]string, 0, len(parsed.Tips))
	seenTips := make(map[string]bool, len(parsed.Tips))
	for _, tip := range parsed.Tips {
		tip = strings.TrimSpace(tip)
		if tip == "" || seenTips[tip] {
			continue
		}
		seenTips[tip] = true
		tips = append(tips, tip)
	}

	tags = make([]string, 0, len(parsed.Tags))
	seenTags := make(map[string]bool, len(parsed.Tags))
	for _, tag := range parsed.Tags {
		if len(tags) >= maxTags {
			break
		}
		// Keep only the first word so tags stay single-word keywords.
		fields := strings.Fields(strings.TrimSpace(strings.TrimPrefix(strings.ToLower(tag), "#")))
		if len(fields) == 0 {
			continue
		}
		tag = strings.Trim(fields[0], ",.;:")
		if tag == "" || seenTags[tag] {
			continue
		}
		seenTags[tag] = true
		tags = append(tags, tag)
	}
	return tips, tags, nil
}
