output "public_ip" {
  description = "Public IPv4 address of the OCI Apps instance"
  value       = oci_core_instance.apps.public_ip
}

output "instance_name" {
  description = "Display name of the instance"
  value       = oci_core_instance.apps.display_name
}

output "instance_id" {
  description = "OCID of the instance"
  value       = oci_core_instance.apps.id
}

output "availability_domain" {
  description = "Target availability domain"
  value       = local.target_ad
}

output "region" {
  description = "OCI region"
  value       = var.region
}

output "expected_cost" {
  description = "Expected monthly cost"
  value       = "€0 (OCI Always Free)"
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ./generated/id_ed25519 ubuntu@${oci_core_instance.apps.public_ip}"
}
