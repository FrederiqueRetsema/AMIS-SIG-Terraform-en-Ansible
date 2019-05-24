##################################################################################
# VARIABLES
##################################################################################

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "compartment_id" {}
variable "region" {
    default = "eu-frankfurt-1"
}
variable "websitetext" {
    default = "Hello, World!"
}
variable "private_key_path" {
    default = "D:\\SIG\\opi_api_key.pem"
}
variable "public_key_path_instance" {
    default = "D:\\SIG\\id_rsa.pub"
}
variable "user_data_control_file" {
    default = "D:\\SIG\\terraform\\user_data_control.sh"
}
variable "user_data_node_file" {
    default = "D:\\SIG\\terraform\\user_data_node.sh"
}

##################################################################################
# PROVIDERS
##################################################################################

provider "oci" {
  tenancy_ocid     = "${var.tenancy_ocid}"
  user_ocid        = "${var.user_ocid}"
  fingerprint      = "${var.fingerprint}"
  region           = "${var.region}"
  private_key_path = "${var.private_key_path}"
}

##################################################################################
# DATA
##################################################################################

data "oci_identity_availability_domains" "availability" {
  compartment_id = "${var.compartment_id}"
}

data "oci_core_images" "oracle_linux_images" {
  compartment_id = "${var.tenancy_ocid}"
  operating_system = "Oracle Linux"
  shape = "VM.Standard2.1"
}

data "template_file" "user_data_control_file" {
  template = "${file("${var.user_data_control_file}")}"
  vars {
    first_ip_address = "${element(oci_core_instance.sig_node.*.private_ip,0)}"
    second_ip_address = "${element(oci_core_instance.sig_node.*.private_ip,1)}"
  }
}

data "template_file" "user_data_node_file" {
  template = "${file("${var.user_data_node_file}")}"
  vars {
    websitetext = "${var.websitetext}"  
  }
}

##################################################################################
# RESOURCES
#
# Een aantal uitgangspunten:
# - Oplossing moet werken binnen een gratis Oracle Cloud account, dus max 1 VM
#   per AZ. Daarom dus ook 3 subnets.
##################################################################################

resource "oci_core_virtual_network" "vcn_sig" {
  compartment_id = "${var.compartment_id}"
  display_name = "vcn_sig"
  cidr_block = "10.0.0.0/16"
  dns_label = "vcnsig"
}

resource "oci_core_internet_gateway" "vcn_sig_igw" {
  compartment_id = "${var.compartment_id}"
  vcn_id = "${oci_core_virtual_network.vcn_sig.id}"
  display_name = "vcn_sig_igw"
  enabled = "true"
}

resource "oci_core_route_table" "vcn_sig_rt" {
  compartment_id = "${var.compartment_id}"
  vcn_id = "${oci_core_virtual_network.vcn_sig.id}"
  display_name = "vcn_sig_rt"
  route_rules {
    destination = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.vcn_sig_igw.id}"
  }
}

resource "oci_core_security_list" "vcn_sig_sl" {
  compartment_id = "${var.compartment_id}"
  vcn_id = "${oci_core_virtual_network.vcn_sig.id}"
  display_name = "vcn_sig_sl"
  egress_security_rules = [
    { destination = "0.0.0.0/0" protocol = "all"}
  ]
  ingress_security_rules = [
    { protocol = "6", source = "0.0.0.0/0", tcp_options { "max" = 22, "min" = 22 }},
    { protocol = "6", source = "0.0.0.0/0", tcp_options { "max" = 80, "min" = 80 }},
    { protocol = "1", source = "10.0.0.0/16"}
  ]
}

resource "oci_core_subnet" "sig_subnet" {
  count=3

  compartment_id = "${var.compartment_id}"
  vcn_id = "${oci_core_virtual_network.vcn_sig.id}"
  display_name = "sig_subnet"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability.availability_domains[count.index], "name")}"
  cidr_block = "10.0.${count.index+1}.0/24"
  route_table_id = "${oci_core_route_table.vcn_sig_rt.id}"
  security_list_ids = ["${oci_core_security_list.vcn_sig_sl.id}"]
  dhcp_options_id = "${oci_core_virtual_network.vcn_sig.default_dhcp_options_id}"
  dns_label = "sigsubnet${count.index+1}"
}

resource "oci_core_instance" "sig_control" {
  compartment_id = "${var.compartment_id}"
  display_name = "control_node"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability.availability_domains[0], "name")}"

  source_details {
    source_id = "${lookup(data.oci_core_images.oracle_linux_images.images[0], "id")}"
    source_type = "image"
  }
  shape = "VM.Standard2.1"
  create_vnic_details {
    subnet_id = "${element(oci_core_subnet.sig_subnet.*.id, 0)}"
    display_name = "primary-vnic"
    assign_public_ip = true
    private_ip = "10.0.1.2"
    hostname_label = "sigcontrolnode"
  }
  metadata {
    ssh_authorized_keys = "${file(var.public_key_path_instance)}"
    user_data = "${base64encode(data.template_file.user_data_control_file.rendered)}"
  }
  timeouts {
    create = "5m"
  }
}

resource "oci_core_instance" "sig_node" {
  count="2"
  
  compartment_id = "${var.compartment_id}"
  display_name = "sig_node"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability.availability_domains["${count.index+1}"], "name")}"

  source_details {
    source_id = "${lookup(data.oci_core_images.oracle_linux_images.images[0], "id")}"
    source_type = "image"
  }
  shape = "VM.Standard2.1"
  create_vnic_details {
    subnet_id = "${element(oci_core_subnet.sig_subnet.*.id, count.index+1)}"
    display_name = "primary-vnic"
    assign_public_ip = true
    private_ip = "10.0.${count.index+2}.${count.index+3}"
    hostname_label = "signode"
  }
  metadata {
    ssh_authorized_keys = "${file(var.public_key_path_instance)}"
    user_data = "${base64encode(data.template_file.user_data_node_file.rendered)}"
  }
  timeouts {
    create = "5m"
  }
}

##################################################################################
# OUTPUT
##################################################################################
output "IP-adres control instance" {
  value = "${oci_core_instance.sig_control.public_ip}"
}
output "IP-adres node 1" {
  value = "${element(oci_core_instance.sig_node.*.public_ip,0)}"
}
output "IP-adres node 2" {
  value = "${element(oci_core_instance.sig_node.*.public_ip,1)}"
}

