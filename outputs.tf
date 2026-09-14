# Values printed after `apply`; also readable any time with `./tf output [-raw] <name>`.

output "backend_public_ip" {
  description = "Elastic IP of the backend VM."
  value       = aws_eip.backend.public_ip
}

output "backend_ssh" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -i ~/.ssh/pinch-aws ubuntu@${aws_eip.backend.public_ip}"
}

output "backend_url" {
  description = "Where the backend will answer once deployed (plain HTTP for now; TLS + domain is a later step)."
  value       = "http://${aws_eip.backend.public_ip}:8000"
}

output "backend_ami" {
  description = "The Ubuntu AMI that was selected (changes as Canonical publishes new builds)."
  value       = data.aws_ami.ubuntu.id
}

output "neon_database_host" {
  description = "Neon Postgres host (no credentials)."
  value       = neon_project.pinch.database_host
}

output "neon_connection_uri" {
  description = "Full Postgres connection string incl. password. `./tf output -raw neon_connection_uri`"
  value       = neon_project.pinch.connection_uri
  sensitive   = true
}
