package handler

import (
	"context"
	"errors"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "tratrack/service/api/pb"
	"tratrack/service/internal/service"
	"tratrack/service/models"
)

type Handler struct {
	pb.UnimplementedAnalysisServiceServer
	svc *service.Service
}

func New(svc *service.Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) StartAnalysis(ctx context.Context, req *pb.StartAnalysisRequest) (*pb.StartAnalysisResponse, error) {
	if strings.TrimSpace(req.GetIdFile()) == "" {
		return nil, status.Error(codes.InvalidArgument, "id_file is required")
	}
	job, err := h.svc.StartAnalysis(ctx, req.GetIdFile())
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create job: %v", err)
	}
	return &pb.StartAnalysisResponse{JobId: job.ID, Status: toProtoStatus(job.Status)}, nil
}

func (h *Handler) StatusAnalysis(ctx context.Context, req *pb.StatusAnalysisRequest) (*pb.StatusAnalysisResponse, error) {
	job, err := h.lookup(ctx, req.GetJobId())
	if err != nil {
		return nil, err
	}
	resp := &pb.StatusAnalysisResponse{
		JobId: job.ID, IdFile: job.IDFile, Status: toProtoStatus(job.Status),
		ProgressPercent: int32(job.ProgressPercent), Error: job.Error,
		CreatedAt: job.CreatedAt.Format(time.RFC3339), UpdatedAt: job.UpdatedAt.Format(time.RFC3339),
	}
	if job.FinishedAt != nil {
		resp.FinishedAt = job.FinishedAt.Format(time.RFC3339)
	}
	return resp, nil
}

func (h *Handler) LastResult(ctx context.Context, _ *pb.LastResultRequest) (*pb.LastResultResponse, error) {
	job, err := h.svc.LastResult(ctx)
	if errors.Is(err, models.ErrNotFound) {
		return nil, status.Error(codes.NotFound, "no completed analysis yet")
	}
	if err != nil {
		return nil, status.Errorf(codes.Internal, "last result: %v", err)
	}
	resp := &pb.LastResultResponse{
		JobId: job.ID, IdFile: job.IDFile, Status: toProtoStatus(job.Status), ResultJson: job.ResultJSON,
	}
	if job.FinishedAt != nil {
		resp.FinishedAt = job.FinishedAt.Format(time.RFC3339)
	}
	return resp, nil
}

// SubscribeAnalysis is the push channel: the macOS UI opens it after
// StartAnalysis and is notified on this stream the moment the job finishes,
// instead of polling StatusAnalysis for 5-8 minutes.
func (h *Handler) SubscribeAnalysis(req *pb.SubscribeAnalysisRequest, stream pb.AnalysisService_SubscribeAnalysisServer) error {
	job, err := h.lookup(stream.Context(), req.GetJobId())
	if err != nil {
		return err
	}

	ch, unsubscribe := h.svc.Subscribe(job.ID)
	defer unsubscribe()

	// Immediate snapshot so a UI (re)connecting mid-job sees current state.
	if err := stream.Send(toEvent(job)); err != nil {
		return err
	}
	if job.Status.IsTerminal() {
		return nil
	}
	for {
		select {
		case <-stream.Context().Done():
			return stream.Context().Err()
		case update := <-ch:
			if err := stream.Send(toEvent(update)); err != nil {
				return err
			}
			if update.Status.IsTerminal() {
				return nil
			}
		}
	}
}

func (h *Handler) lookup(ctx context.Context, jobID string) (*models.Job, error) {
	if strings.TrimSpace(jobID) == "" {
		return nil, status.Error(codes.InvalidArgument, "job_id is required")
	}
	job, err := h.svc.StatusAnalysis(ctx, jobID)
	if errors.Is(err, models.ErrNotFound) {
		return nil, status.Error(codes.NotFound, "job not found")
	}
	if err != nil {
		return nil, status.Errorf(codes.Internal, "get job: %v", err)
	}
	return job, nil
}

func toProtoStatus(s models.Status) pb.JobStatus {
	switch s {
	case models.StatusPending:
		return pb.JobStatus_PENDING
	case models.StatusRunning:
		return pb.JobStatus_RUNNING
	case models.StatusCompleted:
		return pb.JobStatus_COMPLETED
	case models.StatusFailed:
		return pb.JobStatus_FAILED
	default:
		return pb.JobStatus_JOB_STATUS_UNSPECIFIED
	}
}

func toEvent(job *models.Job) *pb.AnalysisEvent {
	ev := &pb.AnalysisEvent{
		JobId: job.ID, IdFile: job.IDFile, Status: toProtoStatus(job.Status),
		ProgressPercent: int32(job.ProgressPercent), Error: job.Error,
		UpdatedAt: job.UpdatedAt.Format(time.RFC3339),
	}
	if job.Status == models.StatusCompleted {
		ev.ResultJson = job.ResultJSON
	}
	return ev
}
