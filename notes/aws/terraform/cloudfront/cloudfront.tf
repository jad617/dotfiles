module "cloudfront" {
  source = "git::https://github.com/jad617/terraform-modules.git//cloudfront?ref=0.26.2"

  name = var.name

  aliases_url  = ["projectX.nodestack.ca"]
  acm_cert_arn = data.aws_acm_certificate.nodestack.arn

  buckets        = module.s3.created_buckets
  default_bucket = "projectX"

  common_tags = local.common_tags
}
