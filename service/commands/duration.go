package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

var numberRe = regexp.MustCompile(`\d+(?:\.\d+)?`)

// Duration enriches each place in inputJSON with the estimated average time
// (in minutes) a visitor spends there. It returns the updated VideoAnalysis
// JSON string.
func Duration(ctx context.Context, apiKey, fileID, inputJSON string) (string, error) {
	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(inputJSON), &analysis); err != nil {
		return "", fmt.Errorf("parsing input JSON: %w", err)
	}
	if analysis.Places == nil {
		analysis.Places = []Place{}
	}

	for i := range analysis.Places {
		p := &analysis.Places[i]
		spent, err := askSpent(ctx, apiKey, fileID, analysis, *p)
		if err != nil {
			return "", fmt.Errorf("place %q: %w", p.Name, err)
		}
		p.Spent = spent
	}

	out, err := json.Marshal(analysis)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func askSpent(ctx context.Context, apiKey, fileID string, analysis VideoAnalysis, place Place) (int, error) {
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
					map[string]any{"type": "input_text", "text": prompt},
					map[string]any{"type": "input_file", "file_id": fileID},
				},
			},
		},
	}

	text, err := museCall(ctx, apiKey, payload)
	if err != nil {
		return 0, err
	}
	return parseSpent(text)
}

type spentResponse struct {
	Spent json.RawMessage `json:"spent"`
}

func parseSpent(text string) (int, error) {
	var parsed spentResponse
	if err := json.Unmarshal([]byte(cleanJSON(text)), &parsed); err != nil {
		return 0, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}
	return normalizeSpent(parsed.Spent), nil
}

// normalizeSpent converts model outputs like 120, "120", "120 minutes", or
// "2 hours" into an integer number of minutes. Ranges are averaged.
// Values outside (0, 1440] become 0 (unknown).
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
