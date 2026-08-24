variable "oci_profile" {
  type        = string
  description = "OCI CLI profile name in ~/.oci/config"
  default     = "DEFAULT"
}

variable "region" {
  type        = string
  description = "OCI target region (must be home region for Always Free resources)"
  default     = "eu-frankfurt-1"
}

variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID. If omitted, the root tenancy OCID is used."
  default     = null
}

variable "availability_domain_number" {
  type        = number
  description = "Target Availability Domain index (1, 2, or 3)."
  default     = 1
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to local SSH public key. Default: ../generated/id_ed25519.pub"
  default     = "../generated/id_ed25519.pub"
}

variable "ssh_public_key" {
  type        = string
  description = "Explicit SSH public key string (takes precedence over ssh_public_key_path if set)"
  default     = null
}

variable "instance_name" {
  type        = string
  description = "Display name for the compute instance and network resources"
  default     = "oci-apps"
}

variable "ocpus" {
  type        = number
  description = "Number of OCPUs for VM.Standard.A1.Flex (Always Free allocation: 1 OCPU)"
  default     = 1
}

variable "memory_in_gbs" {
  type        = number
  description = "Amount of RAM in GB for VM.Standard.A1.Flex (Always Free allocation: 6 GB)"
  default     = 6
}

variable "boot_volume_size_in_gbs" {
  type        = number
  description = "Boot volume size in GB (Always Free allowance)"
  default     = 50
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR block permitted to connect via SSH"
  default     = "0.0.0.0/0"
}
