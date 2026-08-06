package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type Secret struct {
	ID    string `dynamodbav:"id"`
	Key   string `dynamodbav:"key"`
	Value string `dynamodbav:"value"`
}
type CreateSecretRequest struct {
	ID    string `json:"id"`
	Key   string `json:"key"`
	Value string `json:"value"`
}

var dynamoClient *dynamodb.Client
var tableName string

func init() {
	cfg, err := config.LoadDefaultConfig(context.Background())

	if err != nil {
		panic(err)
	}

	dynamoClient = dynamodb.NewFromConfig(cfg)
	tableName = os.Getenv("DYNAMODB_TABLE")
}

func test(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// key := request.PathParameters["key"]

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       "Hello from Lambda !",
		Headers:    map[string]string{"Content-Type": "text/plain"},
	}, nil
}

func getSecret(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	key := request.PathParameters["key"]

	if key == "" {
		return errorResponse(400, "Missing key parameter")
	}

	fmt.Println("Fetching secret:", key)

	result, err := dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &tableName,
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: key},
		},
	})
	if err != nil {
		fmt.Println("Error reading from DynamoDB:", err)
		return errorResponse(500, "Failed to retrieve secret from database")
	}

	if result.Item == nil {
		return errorResponse(404, fmt.Sprintf("Secret with id %s not found", key))
	}

	var secret Secret
	err = attributevalue.UnmarshalMap(result.Item, &secret)
	if err != nil {
		fmt.Println("Error unmarshaling item:", err)
		return errorResponse(500, "Failed to process user data")
	}

	responseBody, _ := json.Marshal(secret)

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(responseBody),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func addSecret(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var req CreateSecretRequest

	err := json.Unmarshal([]byte(request.Body), &req)

	if err != nil {
		return errorResponse(400, "Invalid request body")
	}
	if req.Key == "" || req.Value == "" {
		return errorResponse(400, "Missing required fields")
	}

	secret := Secret{
		ID:    req.ID,
		Key:   req.Key,
		Value: req.Value,
	}

	av, err := attributevalue.MarshalMap(secret)
	if err != nil {
		fmt.Println("Error marshaling item:", err)
		return errorResponse(500, "Failed to process item")
	}

	_, err = dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &tableName,
		Item:      av,
	})
	if err != nil {
		fmt.Println("Error writing to DynamoDB:", err)
		return errorResponse(500, "Failed to save user to database")
	}

	response := map[string]interface{}{
		"message": "Secret created successfully",
		// "secret":    secret,
	}

	responseBody, _ := json.Marshal(response)

	return events.APIGatewayProxyResponse{
		StatusCode: 201,
		Body:       string(responseBody),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func Handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	fmt.Println("Received request:", request.HTTPMethod, request.Path)

	if request.HTTPMethod == "POST" && request.Path == "/create" {
		return addSecret(ctx, request)
	} else if request.HTTPMethod == "GET" && request.Path == "/test" {
		return test(ctx, request)
	} else if request.HTTPMethod == "GET" && request.Path == "/secret/{key}" {
		return getSecret(ctx, request)
	}

	return errorResponse(404, "Endpoint not found")
}

func main() {
	lambda.Start(Handler)
}

func errorResponse(statusCode int, message string) (events.APIGatewayProxyResponse, error) {
	response := map[string]string{
		"error": message,
	}
	responseBody, _ := json.Marshal(response)

	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Body:       string(responseBody),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}
