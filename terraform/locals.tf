data "oci_identity_tenancy" "current" {
  tenancy_id = "ocid1.tenancy.oc1..aaaaaaaa5w3yc4n6f6y3nz4nmccpqlkm66sjbifwwo4w6aut4yybk5ybqxga"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "tls_private_key" "auto_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.auto_ssh.private_key_openssh
  filename        = "${path.module}/../generated/id_ed25519"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.auto_ssh.public_key_openssh
  filename        = "${path.module}/../generated/id_ed25519.pub"
  file_permission = "0644"
}

locals {
  compartment_id = var.compartment_id != null ? var.compartment_id : data.oci_identity_tenancy.current.id

  # AD selection: 0-indexed (AD 1 -> index 0)
  ad_index  = var.availability_domain_number - 1
  target_ad = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name

  # Latest Ubuntu 24.04 ARM64 image
  ubuntu_image_id = data.oci_core_images.ubuntu_arm.images[0].id

  # SSH public key resolution
  ssh_public_key = var.ssh_public_key != null ? var.ssh_public_key : trimspace(tls_private_key.auto_ssh.public_key_openssh)
}

