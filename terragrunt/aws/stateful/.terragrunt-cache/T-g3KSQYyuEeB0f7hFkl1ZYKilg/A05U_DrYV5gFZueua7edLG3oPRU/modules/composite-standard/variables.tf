#------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------
# The single input. One YAML document per client+environment drives every
# stack; nothing is passed as ordinary tfvars.
#------------------------------------------------------------------

variable "config" {
  description = "Configuration settings for the module"
  type        = string
}
