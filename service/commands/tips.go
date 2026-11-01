package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

const maxTags = 7

// Tips enriches each place in inputJSON with travel tips and tags extracted
// from the video segment corresponding to that place. It returns the updated
// VideoAnalysis JSON string.
func Tips(ctx context.Context, apiKey, fileID, inputJSON string) (string, error) {
	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(inputJSON), &analysis); err != nil {
		return "", fmt.Errorf("parsing input JSON: %w", err)
	}
	if analysis.Places == nil {
		analysis.Places = []Place{}
	}

	for i := range analysis.Places {
		p := &analysis.Places[i]
		tips, tags, err := askTips(ctx, apiKey, fileID, *p)
		if err != nil {
			return "", fmt.Errorf("place %q: %w", p.Name, err)
		}
		p.Tips = tips
		p.Tags = tags
	}

	out, err := json.Marshal(analysis)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func askTips(ctx context.Context, apiKey, fileID string, place Place) (tips, tags []string, err error) {
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
					map[string]any{"type": "input_text", "text": prompt},
					map[string]any{"type": "input_file", "file_id": fileID},
				},
			},
		},
	}

	text, err := museCall(ctx, apiKey, payload)
	if err != nil {
		return nil, nil, err
	}
	return parseTips(text)
}

type tipsResponse struct {
	Tips []string `json:"tips"`
	Tags []string `json:"tags"`
}

func parseTips(text string) (tips, tags []string, err error) {
	var parsed tipsResponse
	if err := json.Unmarshal([]byte(cleanJSON(text)), &parsed); err != nil {
		return nil, nil, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	tips = make([]string, 0, len(parsed.Tips))
	seenTips := make(map[string]bool)
	for _, tip := range parsed.Tips {
		tip = strings.TrimSpace(tip)
		if tip == "" || seenTips[tip] {
			continue
		}
		seenTips[tip] = true
		tips = append(tips, tip)
	}

	tags = make([]string, 0, len(parsed.Tags))
	seenTags := make(map[string]bool)
	for _, tag := range parsed.Tags {
		if len(tags) >= maxTags {
			break
		}
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
