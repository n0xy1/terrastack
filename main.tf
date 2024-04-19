terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~>1.53.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~>0.5"
    }
  }
}
# Pull the saved creds from the sops file
data "sops_file" "proj-secrets" {
  source_file = "proj-secrets.enc.json"
}

# Setup the credentials for openstack
provider "openstack" {
  user_name   = "admin"
  tenant_name = "Walshy"
  password    = data.sops_file.proj-secrets.data["openstack-password-quokka"]
  auth_url    = "https://10.100.0.254:5000"
  region      = "RegionOne"
}


# Test resource
resource "openstack_compute_instance_v2" "win-server" {
  count      = 3
  name       = "win-server-${count.index}"
  flavor_id  = "3"
  admin_pass = "P@ssw0rd"
  # key_pair        = "id_ed25519"
  security_groups = ["default"]

  # for some reason the windows images need to boot the the volume (not just the image).. 
  block_device {
    uuid                  = "190f1111-97dc-4544-9f26-71787dd43337"
    source_type           = "image"
    volume_size           = 42
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  network {
    uuid           = openstack_networking_network_v2.goad_internal.id
    access_network = true
  }
}

# Build a router, an internal network and link em.
resource "openstack_networking_router_v2" "ext_router" {
  name                = "goad_router"
  admin_state_up      = true
  external_network_id = "8ebb797c-7398-4615-9a6b-df8782b4623f"
}

resource "openstack_networking_network_v2" "goad_internal" {
  name           = "goad_internal"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "goad_internal_subnet" {
  network_id = openstack_networking_network_v2.goad_internal.id
  cidr       = "10.250.2.0/24"
  ip_version = 4
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.ext_router.id
  subnet_id = openstack_networking_subnet_v2.goad_internal_subnet.id
}



# BUILD THE BASTION FOR ANSIBLE HANDOFF.
resource "openstack_compute_instance_v2" "bastion_host" {
  name            = "bastion"
  image_id        = "58e46228-bf3c-4cc9-a281-75a2210eb01d"
  flavor_id       = "2" # Example flavor
  key_pair        = "id_ed25519"
  security_groups = ["default"]

  network {
    uuid           = openstack_networking_network_v2.goad_internal.id
    access_network = true
  }
}
resource "openstack_networking_floatingip_v2" "bastion_fip" {
  pool = "public1"
}

resource "openstack_compute_floatingip_associate_v2" "bastion_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.bastion_fip.address
  instance_id = openstack_compute_instance_v2.bastion_host.id
}

# BUILD THE ATTACK BOX
resource "openstack_compute_instance_v2" "attacker_host" {
  name            = "attack"
  image_id        = "b482beae-2a17-4214-84eb-b53a865e9669"
  flavor_id       = 4
  key_pair        = "id_ed25519"
  security_groups = ["default"]
  network {
    uuid           = openstack_networking_network_v2.goad_internal.id
    access_network = true
  }
}
resource "openstack_networking_floatingip_v2" "attacker_fip" {
  pool = "public1"
}

resource "openstack_compute_floatingip_associate_v2" "attacker_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.attacker_fip.address
  instance_id = openstack_compute_instance_v2.attacker_host.id
}


# OUTPUTS
output "bastion_ip" {
  value = openstack_networking_floatingip_v2.bastion_fip.address
}

output "instance_ips" {
  value = [for instance in openstack_compute_instance_v2.win-server : instance.access_ip_v4]
}


# BUILD INVENTORY
locals {
  bastion_ip   = openstack_networking_floatingip_v2.bastion_fip.address
  instance_ips = [for instance in openstack_compute_instance_v2.win-server : instance.network.0.fixed_ip_v4]
  attacker_ip  = openstack_networking_floatingip_v2.attacker_fip.address
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    bastion_ip  = local.bastion_ip
    ips         = local.instance_ips
    attacker_ip = local.attacker_ip
  })
  filename = "${path.module}/ansible/inventory.ini"
}

output "ssh_command" {
  value = "Infrastructure has been provisioned.\nTo commence configuration with ansible first run the command:\n\n\tssh -D 10080 ubuntu@${local.bastion_ip}\n\nFollowed by the ansible playbook you want to run.\n\n Once the domain is configured, your attacked box has the following ip:\n\t${local.attacker_ip}"
}
