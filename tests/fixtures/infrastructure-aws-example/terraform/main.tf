resource "aws_ssm_parameter" "example" {
  name  = "/example/${var.environment}/region"
  type  = "String"
  value = var.region
}
