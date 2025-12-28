output "ec2_public_dns" {
  value = aws_instance.app.public_dns
}

output "hello_url" {
  value = "http://${aws_instance.app.public_dns}/hello"
}

output "ecr_frontend_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repo_url" {
  value = aws_ecr_repository.backend.repository_url
}
