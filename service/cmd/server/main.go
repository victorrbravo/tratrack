package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	pb "tratrack/service/api/pb"
	"tratrack/service/internal/config"
	"tratrack/service/internal/handler"
	"tratrack/service/internal/service"
	"tratrack/service/models"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()
	store, err := models.Open(cfg.DSN)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer store.Close()
	if err := store.Migrate(ctx); err != nil {
		log.Fatalf("migrate analysis_jobs: %v", err)
	}
	if err := store.FailInterrupted(ctx); err != nil {
		log.Fatalf("fail interrupted jobs: %v", err)
	}

	var analyzer service.Analyzer
	if cfg.ModelAPIKey != "" {
		log.Printf("using Muse API analyzer (location: %s)", cfg.AnalysisLocation)
		analyzer = service.MuseAnalyzer{APIKey: cfg.ModelAPIKey, Location: cfg.AnalysisLocation}
	} else {
		log.Printf("MODEL_API_KEY not set — using simulated analyzer (duration %s)", cfg.AnalysisDuration)
		analyzer = service.SimulatedAnalyzer{Duration: cfg.AnalysisDuration}
	}
	svc := service.New(store, analyzer, cfg.JobTimeout)

	lis, err := net.Listen("tcp", cfg.GRPCAddr)
	if err != nil {
		log.Fatalf("listen %s: %v", cfg.GRPCAddr, err)
	}
	server := grpc.NewServer()
	pb.RegisterAnalysisServiceServer(server, handler.New(svc))
	reflection.Register(server)

	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		<-sig
		log.Println("shutting down...")
		stopped := make(chan struct{})
		go func() { server.GracefulStop(); close(stopped) }()
		select {
		case <-stopped:
		case <-time.After(10 * time.Second):
			server.Stop()
		}
	}()

	log.Printf("analysis gRPC service listening on %s (analysis duration %s)", cfg.GRPCAddr, cfg.AnalysisDuration)
	if err := server.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
