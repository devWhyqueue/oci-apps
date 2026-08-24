resource "oci_core_instance" "apps" {
  availability_domain = local.target_ad
  compartment_id      = local.compartment_id
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = local.ubuntu_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    display_name     = "${var.instance_name}-vnic"
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.apps.id]
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {}))
  }

  preserve_boot_volume = false
}
