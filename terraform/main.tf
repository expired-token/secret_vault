terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

/* --- API GATEWAY --- */

// Create HTTP API Gateway
resource "aws_apigatewayv2_api" "test_api" {
  name          = "test-http-api"
  protocol_type = "HTTP"
}

// Define it as Test environment API Gateway
resource "aws_apigatewayv2_stage" "test_stage" {
  api_id      = aws_apigatewayv2_api.test_api.id
  name        = "test"
  auto_deploy = true
}

// Integrate API Gateway with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.test_api.id
  integration_type   = "AWS_PROXY" // for sending/returning the whole HTTP request/response to/from Lambda
  integration_method = "POST"      // API Gateway always invokes Lambda using POST, regardless of what the client sent/requested
  integration_uri    = aws_lambda_function.test_lambda.invoke_arn
}

// Define route for API Gateway
resource "aws_apigatewayv2_route" "test_route" {
  api_id    = aws_apigatewayv2_api.test_api.id
  route_key = "GET /test"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
resource "aws_apigatewayv2_route" "create_secret" {
  api_id    = aws_apigatewayv2_api.test_api.id
  route_key = "POST /create"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

/* --- LAMBDA FUNCTION --- */

// Define resource-based, lambda permission to grant API Gateway access to Lambda
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.test_api.execution_arn}/*/*"
}

// Define Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "lambda.amazonaws.com"
          }
        }
      ]
    }
  )
}

// Define lambda execution policy + attach it to lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" // allow limited write permissions for lambda to log things on CloudWatch 
}

/*resource "aws_iam_role_policy_attachement" "lambda_dynamodb" {
    role = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}*/

// Define dynamodb access policy + attach it to lambda 
resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            //"dynamodb:Query",
            //"dynamodb:Scan",
          ]
          Effect   = "Allow"
          Resource = aws_dynamodb_table.test_table.arn
        },
      ]
    }
  )
}

// Create Lambda Function
resource "aws_lambda_function" "test_lambda" {
  filename         = "test_code.zip"
  function_name    = "test_function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = "provided.al2"
  architectures    = ["arm64"]
  source_code_hash = filebase64sha256("test_code.zip") // automatically detects code changes in the file to trigger a terraform redeployment

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.test_table.name
    }
  }
}

/* --- DYNAMODB --- */

// Create dynamodb database
resource "aws_dynamodb_table" "test_table" {
  name         = "vault-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    environment = "test"
  }
}


output "api_endpoint" {
  value = aws_apigatewayv2_stage.test_stage.invoke_url
}

