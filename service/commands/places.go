package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// Places calls the Muse API to extract every place visited, shown, or named in
// the travel video identified by fileID. It returns the result as a JSON string
// matching the VideoAnalysis schema.
func Places(ctx context.Context, apiKey, fileID string) (string, error) {
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

	text, err := museCall(ctx, apiKey, payload)
	if err != nil {
		return "", err
	}
	analysis, err := parsePlaces(text)
	if err != nil {
		return "", err
	}
	out, err := json.Marshal(analysis)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func parsePlaces(text string) (VideoAnalysis, error) {
	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(cleanJSON(text)), &analysis); err != nil {
		return VideoAnalysis{}, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	analysis.Name = strings.TrimSpace(analysis.Name)
	analysis.Summary = strings.TrimSpace(analysis.Summary)

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
