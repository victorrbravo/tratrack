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
	"regexp"
	"sort"
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
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	StartSeconds float64 `json:"start_seconds"`
	EndSeconds   float64 `json:"end_seconds"`
	Location     string  `json:"location"`
	// Extra holds every other field present in the input place (tips,
	// tags, spent, ...) so it is preserved unchanged in the output.
	Extra map[string]json.RawMessage `json:"-"`
}

var placeKnownKeys = map[string]bool{
	"id": true, "name": true, "start_seconds": true, "end_seconds": true,
	"start": true, "end": true, "location": true,
}

// UnmarshalJSON also accepts "start"/"end" as aliases for
// "start_seconds"/"end_seconds" and captures unknown fields into Extra.
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

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	for key := range raw {
		if placeKnownKeys[key] {
			delete(raw, key)
		}
	}
	if len(raw) > 0 {
		p.Extra = raw
	}
	return nil
}

// MarshalJSON writes the known fields plus every field captured in Extra.
func (p Place) MarshalJSON() ([]byte, error) {
	type Alias Place
	out, err := json.Marshal((*Alias)(&p))
	if err != nil || len(p.Extra) == 0 {
		return out, err
	}

	keys := make([]string, 0, len(p.Extra))
	for key := range p.Extra {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	var buf bytes.Buffer
	buf.Write(out[:len(out)-1]) // strip trailing '}'
	for _, key := range keys {
		keyJSON, err := json.Marshal(key)
		if err != nil {
			return nil, err
		}
		buf.WriteByte(',')
		buf.Write(keyJSON)
		buf.WriteByte(':')
		buf.Write(p.Extra[key])
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}

type VideoAnalysis struct {
	Name    string  `json:"name"`
	Summary string  `json:"summary"`
	Places  []Place `json:"places"`
}

type placeLocation struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Location string `json:"location"`
}

type locationResponse struct {
	Places []placeLocation `json:"places"`
}

var locationRe = regexp.MustCompile(`^\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$`)

func main() {
	apiKey := os.Getenv("MODEL_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set MODEL_API_KEY")
		os.Exit(1)
	}

	// Usage:
	//   go run location.go Paris
	//   go run location.go output.json Paris
	//   go run location.go output.json Paris located.json
	inputPath, context, outputPath := parseArgs(os.Args[1:])
	if context == "" {
		fmt.Fprintln(os.Stderr, "Usage: go run location.go [input.json] <city-or-country> [output.json]")
		os.Exit(1)
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

	if len(analysis.Places) > 0 {
		locations, err := askLocations(apiKey, context, analysis.Places)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		for i := range analysis.Places {
			if loc, ok := locations[analysis.Places[i].ID]; ok {
				analysis.Places[i].Location = loc
			}
		}
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

	fmt.Fprintf(os.Stderr, "Wrote %s (%d places, context %q)\n", outputPath, len(analysis.Places), context)
}

func parseArgs(args []string) (inputPath, context, outputPath string) {
	inputPath = "output.json"
	switch len(args) {
	case 1:
		context = args[0]
	case 2:
		inputPath, context = args[0], args[1]
	case 3:
		inputPath, context, outputPath = args[0], args[1], args[2]
	}
	if outputPath == "" {
		ext := filepath.Ext(inputPath)
		base := strings.TrimSuffix(inputPath, ext)
		if ext == "" {
			ext = ".json"
		}
		outputPath = base + "_locations" + ext
	}
	return inputPath, strings.TrimSpace(context), outputPath
}

func askLocations(apiKey, context string, places []Place) (map[int]string, error) {
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
- If you do not know the coordinates of a place, set "location" to "" and do not invent coordinates.`, context, list.String())

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
				},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, apiBaseURL+"/responses", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("calling API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("API error (%s): %s", resp.Status, respBody)
	}

	var result Response
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("invalid API response: %s", respBody)
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
		return nil, fmt.Errorf("empty API response: %s", respBody)
	}

	return parseLocations(strings.Join(texts, "\n"), places)
}

func parseLocations(text string, places []Place) (map[int]string, error) {
	cleaned := strings.TrimSpace(text)
	cleaned = strings.TrimPrefix(cleaned, "```json")
	cleaned = strings.TrimPrefix(cleaned, "```")
	cleaned = strings.TrimSuffix(cleaned, "```")
	cleaned = strings.TrimSpace(cleaned)
	if start, end := strings.Index(cleaned, "{"), strings.LastIndex(cleaned, "}"); start >= 0 && end > start {
		cleaned = cleaned[start : end+1]
	}

	var parsed locationResponse
	if err := json.Unmarshal([]byte(cleaned), &parsed); err != nil {
		return nil, fmt.Errorf("invalid JSON from model: %q: %w", text, err)
	}

	byName := make(map[string]int, len(places))
	for _, p := range places {
		byName[strings.ToLower(strings.TrimSpace(p.Name))] = p.ID
	}

	ids := placeIDSet(places)
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

func placeIDSet(places []Place) map[int]bool {
	set := make(map[int]bool, len(places))
	for _, p := range places {
		set[p.ID] = true
	}
	return set
}

// normalizeLocation validates "(lat,lng)" and rewrites it without spaces.
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
