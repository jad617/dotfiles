variable "buckets" {
  description = "Map of all the buckets to be created"
  type        = any
}

variable "region" {
  type    = string
  default = "ca-central-1"
}

variable "name" {
  default = "projectX"
  type    = string
}

variable "stage" {
  description = "Stage, e.g. 'prd', 'rel,int,stg'"
  type        = string

  validation {
    condition     = contains(["rel", "int", "stg", "prd"], var.stage)
    error_message = "var.stage must be one if the following choices: 'rel', 'int', 'stg' or 'prd'"
  }
}

variable "organisation" {
  type        = string
  description = "Organisation name"

  default = "nodestack"
}

variable "namespace" {
  type        = string
  description = "Namespace name"
}
