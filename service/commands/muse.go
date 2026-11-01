package commands

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

const museAPIBase = "https://api.meta.ai/v1"

type museResponse struct {
	Output []struct {
		Type    string `json:"type"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	} `json:"output"`
}

// Place accumulates all fields produced across the four pipeline steps.
type Place struct {
	ID           int      `json:"id"`
	Name         string   `json:"name"`
	StartSeconds float64  `json:"start_seconds"`
	EndSeconds   float64  `json:"end_seconds"`
	Location     string   `json:"location,omitempty"`
	Tips         []string `json:"tips,omitempty"`
	Tags         []string `json:"tags,omitempty"`
	Spent        int      `json:"spent,omitempty"`
}

// UnmarshalJSON accepts "start"/"end" as aliases for "start_seconds"/"end_seconds".
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

// VideoAnalysis is the top-level result that flows through every pipeline step.
type VideoAnalysis struct {
	Name    string  `json:"name"`
	Summary string  `json:"summary"`
	Places  []Place `json:"places"`
}

// museCall sends one request to the Muse API and returns the first output_text value.
func museCall(ctx context.Context, apiKey string, payload map[string]any) (string, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, museAPIBase+"/responses", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	t0 := time.Now()
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("calling Muse API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	elapsed := time.Since(t0)
	if err != nil {
		return "", err
	}
	log.Printf("[muse] HTTP %s  body=%d bytes  elapsed=%s", resp.Status, len(respBody), elapsed.Round(time.Millisecond))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("Muse API error (%s): %s", resp.Status, respBody)
	}

	var result museResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("invalid Muse API response: %s", respBody)
	}

	var texts []string
	for _, item := range result.Output {
		for _, c := range item.Content {
			if c.Type == "output_text" {
				texts = append(texts, c.Text)
			}
		}
	}
	if len(texts) == 0 {
		return "", fmt.Errorf("empty Muse API response: %s", respBody)
	}
	return strings.Join(texts, "\n"), nil
}

// cleanJSON strips markdown fences and trims prose outside the outermost JSON object.
func cleanJSON(text string) string {
	s := strings.TrimSpace(text)
	s = strings.TrimPrefix(s, "```json")
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(s, "```")
	s = strings.TrimSpace(s)
	if start, end := strings.Index(s, "{"), strings.LastIndex(s, "}"); start >= 0 && end > start {
		s = s[start : end+1]
	}
	return s
}

func formatSeconds(s float64) string {
	total := int(s)
	return fmt.Sprintf("%d:%02d", total/60, total%60)
}
