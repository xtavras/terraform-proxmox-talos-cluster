# ---------------------------------------------------------------------------
# Talos Image Factory: schematic (extensions) + image URLs for talos_version
# ---------------------------------------------------------------------------

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.talos_extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
  # qcow2: ~200 MB and uncompressed. PVE can't decompress for the 'import'
  # content type, and the raw image is ~4.4 GB.
  disk_image_format = "qcow2"
}

locals {
  # Upgrade target of talos_machine and the documented install image.
  talos_installer_image = data.talos_image_factory_urls.this.urls.installer
}

# ---------------------------------------------------------------------------
# Boot disk image on Proxmox.
#
# Follows talos_version, so NEW VMs boot directly at the current version.
# EXISTING VMs ignore image changes (lifecycle in vms.tf) and are upgraded in
# place by talos_machine. The cluster name is part of the file name so that
# several clusters on one PVE node don't fight over the same file.
# ---------------------------------------------------------------------------

resource "proxmox_download_file" "talos" {
  node_name    = var.proxmox.node_name
  datastore_id = var.proxmox.image_datastore
  content_type = "import"

  url       = data.talos_image_factory_urls.this.urls.disk_image
  file_name = "talos-${var.name}-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.qcow2"

  overwrite      = false
  upload_timeout = 1200
}
