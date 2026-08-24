resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_id
  cidr_blocks    = ["10.1.0.0/16"]
  display_name   = "${var.instance_name}-vcn"
  dns_label      = "appsvcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-igw"
  enabled        = true
}

resource "oci_core_default_route_table" "default_route_table" {
  manage_default_resource_id = oci_core_vcn.main.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_network_security_group" "apps" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-nsg"
}

# Egress: allow all outbound traffic
resource "oci_core_network_security_group_security_rule" "egress_all" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic"
}

# Ingress: SSH (TCP 22)
resource "oci_core_network_security_group_security_rule" "ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.allowed_ssh_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Allow SSH management access"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# Ingress: HTTP (TCP 80)
resource "oci_core_network_security_group_security_rule" "ingress_http" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Allow HTTP traffic"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

# Ingress: HTTPS (TCP 443)
resource "oci_core_network_security_group_security_rule" "ingress_https" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Allow HTTPS traffic for Berlin Insider"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Ingress: ICMP Type 3, Code 4 (Path MTU Discovery)
resource "oci_core_network_security_group_security_rule" "ingress_icmp_mtu" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Path MTU Discovery"

  icmp_options {
    type = 3
    code = 4
  }
}

# Ingress: ICMP Type 8 (Echo / Ping)
resource "oci_core_network_security_group_security_rule" "ingress_icmp_echo" {
  network_security_group_id = oci_core_network_security_group.apps.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "ICMP Echo Request"

  icmp_options {
    type = 8
    code = 0
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.1.1.0/24"
  display_name               = "${var.instance_name}-subnet"
  dns_label                  = "appssubnet"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_vcn.main.default_route_table_id
}

