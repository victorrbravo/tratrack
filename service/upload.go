//go:build ignore

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"os"
	"path/filepath"
	"strings"
)

const apiBaseURL = "https://api.meta.ai/v1"

// Uploaded videos are deleted by the API after this many seconds (1 hour is
// the minimum it accepts), so test runs don't pile up in team storage.
const uploadExpirySeconds = "3600"

type UploadedFile struct {
	ID       string `json:"id"`
	Status   string `json:"status"`
	Filename string `json:"filename,omitempty"`
}

func main() {
	apiKey := os.Getenv("MODEL_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set MODEL_API_KEY")
		os.Exit(1)
	}

	// Video to upload: first argument, things.mp4 by default.
	videoPath := "things.mp4"
	if len(os.Args) > 1 {
		videoPath = os.Args[1]
	}
	if len(os.Args) > 2 {
		fmt.Fprintln(os.Stderr, "Usage: go run upload.go [video.mp4]")
		os.Exit(1)
	}

	uploaded, err := uploadVideo(apiKey, videoPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "Uploaded %s as %s (status %s)\n", videoPath, uploaded.ID, uploaded.Status)
	// Only the file_id goes to stdout, so it can be captured directly:
	//   FILE_ID=$(go run upload.go things.mp4)
	//   go run . "$FILE_ID"
	fmt.Println(uploaded.ID)
}

// uploadVideo sends the file to the Files API (POST /v1/files) so a later
// request can reference it by id.
func uploadVideo(apiKey, path string) (UploadedFile, error) {
	if !strings.EqualFold(filepath.Ext(path), ".mp4") {
		return UploadedFile{}, fmt.Errorf("only .mp4 video files are accepted: %s", path)
	}

	video, err := os.Open(path)
	if err != nil {
		return UploadedFile{}, fmt.Errorf("reading video: %w", err)
	}
	defer video.Close()

	var form bytes.Buffer
	writer := multipart.NewWriter(&form)
	// The API recommends sending purpose and expiry before the file.
	fields := [][2]string{
		{"purpose", "user_data"},
		{"expires_after[anchor]", "created_at"},
		{"expires_after[seconds]", uploadExpirySeconds},
	}
	for _, field := range fields {
		if err := writer.WriteField(field[0], field[1]); err != nil {
			return UploadedFile{}, err
		}
	}
	// mp4 is the only video format the API accepts.
	header := textproto.MIMEHeader{}
	header.Set("Content-Disposition",
		fmt.Sprintf(`form-data; name="file"; filename=%q`, filepath.Base(path)))
	header.Set("Content-Type", "video/mp4")
	part, err := writer.CreatePart(header)
	if err != nil {
		return UploadedFile{}, err
	}
	if _, err := io.Copy(part, video); err != nil {
		return UploadedFile{}, fmt.Errorf("reading video: %w", err)
	}
	if err := writer.Close(); err != nil {
		return UploadedFile{}, err
	}

	req, err := http.NewRequest(http.MethodPost, apiBaseURL+"/files", &form)
	if err != nil {
		return UploadedFile{}, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return UploadedFile{}, fmt.Errorf("uploading video: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return UploadedFile{}, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return UploadedFile{}, fmt.Errorf("upload error (%s): %s", resp.Status, respBody)
	}

	var uploaded UploadedFile
	if err := json.Unmarshal(respBody, &uploaded); err != nil || uploaded.ID == "" {
		return UploadedFile{}, fmt.Errorf("invalid upload response: %s", respBody)
	}
	return uploaded, nil
}
