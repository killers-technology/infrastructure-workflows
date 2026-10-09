# Module tests run in CI without cloud credentials: providers are mocked.
mock_provider "aws" {}

run "creates_the_parameter" {
  command = plan

  variables {
    name  = "example/region"
    value = "us-east-1"
  }

  assert {
    condition     = aws_ssm_parameter.this.name == "/example/region"
    error_message = "the parameter name gets a leading slash"
  }
}

run "rejects_an_invalid_name" {
  command = plan

  variables {
    name  = "Example Region"
    value = "us-east-1"
  }

  expect_failures = [var.name]
}
