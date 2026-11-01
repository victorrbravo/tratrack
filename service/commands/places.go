//go:build ignore

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
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
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	StartSeconds float64 `json:"start_seconds"`
	EndSeconds   float64 `json:"end_seconds"`
}

type VideoAnalysis struct {
	Name    string  `json:"name"`
	Summary string  `json:"summary"`
	Places  []Place `json:"places"`
}

func main() {
	apiKey := os.Getenv("MODEL_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set MODEL_API_KEY")
		os.Exit(1)
	}

	// Usage:
	//   go run places.go <file_id>
	//   go run places.go <file_id> output.json
	if len(os.Args) < 2 || strings.TrimSpace(os.Args[1]) == "" || len(os.Args) > 3 {
		fmt.Fprintln(os.Stderr, "Usage: go run places.go <file_id> [output.json]")
		os.Exit(1)
	}
	fileID := strings.TrimSpace(os.Args[1])

	outputPath := "output.json"
	if len(os.Args) > 2 {
		outputPath = os.Args[2]
	}

	analysis, err := analyzeVideo(apiKey, fileID)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
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

// analyzeVideo asks Muse to analyze the travel video identified by
// fileID and extract the places visited or named, with their timestamps.
func analyzeVideo(apiKey, fileID string) (VideoAnalysis, error) {
	payload := map[string]any{
		"model": "muse-spark-1.3",
		"input": []any{
			map[string]any{
				"type": "message",
				"role": "user",
				"content": []any{
					map[string]any{
						"type": "input_text",
						"text": `Analyze this travel video and extract every place that is visited, shown, or named (spoken or written on screen).

Return ONLY a valid JSON object, with no markdown fences and no extra text, in exactly this format:
{"name":"<title or name of the video>","summary":"<short description of the video>","places":[{"id":1,"name":"<place name>","start_seconds":0,"end_seconds":0}]}

Rules:
- Order places chronologically by when they first appear.
- "id" must be an incremental integer starting at 1.
- Include start_seconds and end_seconds (numeric seconds in the video) for each place.
- Do not invent places or timestamps. If a place is only named, use the timestamp where it is named.
- If no places are found, return an empty "places" array.`,
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
		return VideoAnalysis{}, err
	}

	req, err := http.NewRequest(http.MethodPost, apiBaseURL+"/responses", bytes.NewReader(body))
	if err != nil {
		return VideoAnalysis{}, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return VideoAnalysis{}, fmt.Errorf("calling API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return VideoAnalysis{}, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return VideoAnalysis{}, fmt.Errorf("API error (%s): %s", resp.Status, respBody)
	}

	var result Response
	if err := json.Unmarshal(respBody, &result); err != nil {
		return VideoAnalysis{}, fmt.Errorf("invalid API response: %s", respBody)
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
		return VideoAnalysis{}, fmt.Errorf("empty API response: %s", respBody)
	}

	return parseAnalysis(strings.Join(texts, "\n"))
}

func parseAnalysis(text string) (VideoAnalysis, error) {
	cleaned := strings.TrimSpace(text)
	cleaned = strings.TrimPrefix(cleaned, "```json")
	cleaned = strings.TrimPrefix(cleaned, "```")
	cleaned = strings.TrimSuffix(cleaned, "```")
	cleaned = strings.TrimSpace(cleaned)

	// Tolerate extra prose around the JSON object.
	if start, end := strings.Index(cleaned, "{"), strings.LastIndex(cleaned, "}"); start >= 0 && end > start {
		cleaned = cleaned[start : end+1]
	}

	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(cleaned), &analysis); err != nil {
		return VideoAnalysis{}, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	analysis.Name = strings.TrimSpace(analysis.Name)
	analysis.Summary = strings.TrimSpace(analysis.Summary)

	// Reassign ids so they are guaranteed incremental regardless of model output.
	places := make([]Place, 0, len(analysis.Places))
	for _, p := range analysis.Places {
		p.Name = strings.TrimSpace(p.Name)
		if p.Name == "" {
			continue
		}
		if p.EndSeconds < p.StartSeconds {
			p.EndSeconds = p.StartSeconds
		}
		p.ID = len(places) + 1
		places = append(places, p)
	}
	analysis.Places = places

	return analysis, nil
}
