package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

var locationRe = regexp.MustCompile(`^\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$`)

// Location enriches each place in inputJSON with geographic coordinates.
// cityOrCountry is used to disambiguate place names; it defaults to "Paris"
// when empty. Returns the updated VideoAnalysis JSON string.
func Location(ctx context.Context, apiKey, inputJSON, cityOrCountry string) (string, error) {
	if cityOrCountry == "" {
		cityOrCountry = "Paris"
	}

	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(inputJSON), &analysis); err != nil {
		return "", fmt.Errorf("parsing input JSON: %w", err)
	}
	if analysis.Places == nil {
		analysis.Places = []Place{}
	}

	if len(analysis.Places) > 0 {
		locs, err := askLocations(ctx, apiKey, cityOrCountry, analysis.Places)
		if err != nil {
			return "", err
		}
		for i := range analysis.Places {
			if loc, ok := locs[analysis.Places[i].ID]; ok {
				analysis.Places[i].Location = loc
			}
		}
	}

	out, err := json.Marshal(analysis)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

type placeLocation struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Location string `json:"location"`
}

type locationResponse struct {
	Places []placeLocation `json:"places"`
}

func askLocations(ctx context.Context, apiKey, cityOrCountry string, places []Place) (map[int]string, error) {
	var list strings.Builder
	for _, p := range places {
		fmt.Fprintf(&list, "%d. %s\n", p.ID, p.Name)
	}

	prompt := fmt.Sprintf(`For each place below, give its geographic coordinates. All places are in or near: %s. Use that city/country to disambiguate each name (for example, choose the well-known place with that name in that city/country).

Places:
%s
Return ONLY a valid JSON object, with no markdown fences and no extra text, in exactly this format:
{"places":[{"id":1,"name":"<place name>","location":"(<latitude>,<longitude>)"}]}

Rules:
- Return one entry per input place, keeping the same "id" and "name".
- "location" must be a string in the format "(<latitude>,<longitude>)", e.g. "(48.8584,2.2945)".
- Use decimal degrees with at least 4 decimal places.
- If you do not know the coordinates of a place, set "location" to "" and do not invent coordinates.`, cityOrCountry, list.String())

	payload := map[string]any{
		"model": "muse-spark-1.3",
		"input": []any{
			map[string]any{
				"type": "message",
				"role": "user",
				"content": []any{
					map[string]any{"type": "input_text", "text": prompt},
				},
			},
		},
	}

	text, err := museCall(ctx, apiKey, payload)
	if err != nil {
		return nil, err
	}
	return parseLocations(text, places)
}

func parseLocations(text string, places []Place) (map[int]string, error) {
	var parsed locationResponse
	if err := json.Unmarshal([]byte(cleanJSON(text)), &parsed); err != nil {
		return nil, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	byName := make(map[string]int, len(places))
	for _, p := range places {
		byName[strings.ToLower(strings.TrimSpace(p.Name))] = p.ID
	}
	ids := make(map[int]bool, len(places))
	for _, p := range places {
		ids[p.ID] = true
	}

	locations := make(map[int]string, len(parsed.Places))
	for _, p := range parsed.Places {
		loc, err := normalizeLocation(p.Location)
		if err != nil || loc == "" {
			continue
		}
		id := p.ID
		if !ids[id] {
			matched, ok := byName[strings.ToLower(strings.TrimSpace(p.Name))]
			if !ok {
				continue
			}
			id = matched
		}
		locations[id] = loc
	}
	return locations, nil
}

func normalizeLocation(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", nil
	}
	m := locationRe.FindStringSubmatch(s)
	if m == nil {
		return "", fmt.Errorf("invalid location %q", s)
	}
	lat, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		return "", err
	}
	lng, err := strconv.ParseFloat(m[2], 64)
	if err != nil {
		return "", err
	}
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return "", fmt.Errorf("coordinates out of range %q", s)
	}
	return "(" + m[1] + "," + m[2] + ")", nil
}
