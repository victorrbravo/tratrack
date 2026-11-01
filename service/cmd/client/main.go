// Command client exercises the AnalysisService from the terminal.
//
//	go run ./cmd/client -id-file video-123        # start, watch until notified, print result
//	go run ./cmd/client -status <job-id>
//	go run ./cmd/client -last
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "tratrack/service/api/pb"
)

func main() {
	addr := flag.String("addr", "localhost:50051", "gRPC address")
	idFile := flag.String("id-file", "", "start analysis for this id_file")
	statusID := flag.String("status", "", "query status of this job id")
	last := flag.Bool("last", false, "print last completed result")
	flag.Parse()

	conn, err := grpc.NewClient(*addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	client := pb.NewAnalysisServiceClient(conn)
	ctx := context.Background()

	switch {
	case *idFile != "":
		resp, err := client.StartAnalysis(ctx, &pb.StartAnalysisRequest{IdFile: *idFile})
		if err != nil {
			log.Fatalf("StartAnalysis: %v", err)
		}
		fmt.Printf("job_id=%s status=%s\nwatching for completion (server push)...\n", resp.GetJobId(), resp.GetStatus())
		stream, err := client.SubscribeAnalysis(ctx, &pb.SubscribeAnalysisRequest{JobId: resp.GetJobId()})
		if err != nil {
			log.Fatalf("SubscribeAnalysis: %v", err)
		}
		for {
			ev, err := stream.Recv()
			if err == io.EOF {
				break
			}
			if err != nil {
				log.Fatalf("recv: %v", err)
			}
			fmt.Printf("[%s] status=%s progress=%d%%\n", time.Now().Format(time.TimeOnly), ev.GetStatus(), ev.GetProgressPercent())
			if ev.GetStatus() == pb.JobStatus_COMPLETED {
				fmt.Printf("NOTIFIED: job finished\nresult=%s\n", ev.GetResultJson())
				break
			}
			if ev.GetStatus() == pb.JobStatus_FAILED {
				fmt.Printf("NOTIFIED: job failed: %s\n", ev.GetError())
				os.Exit(1)
			}
		}
	case *statusID != "":
		resp, err := client.StatusAnalysis(ctx, &pb.StatusAnalysisRequest{JobId: *statusID})
		if err != nil {
			log.Fatalf("StatusAnalysis: %v", err)
		}
		fmt.Printf("job_id=%s id_file=%s status=%s progress=%d%% error=%q finished_at=%s\n",
			resp.GetJobId(), resp.GetIdFile(), resp.GetStatus(), resp.GetProgressPercent(), resp.GetError(), resp.GetFinishedAt())
	case *last:
		resp, err := client.LastResult(ctx, &pb.LastResultRequest{})
		if err != nil {
			log.Fatalf("LastResult: %v", err)
		}
		fmt.Printf("job_id=%s id_file=%s finished_at=%s\nresult=%s\n",
			resp.GetJobId(), resp.GetIdFile(), resp.GetFinishedAt(), resp.GetResultJson())
	default:
		flag.Usage()
		os.Exit(2)
	}
}
