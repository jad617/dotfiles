module "s3" {
  source = "git::https://github.com/jad617/terraform-modules.git//s3?ref=0.26.2"

  buckets = var.buckets

  acl     = "private"
  kms_arn = ""

  stage       = var.stage
  common_tags = local.common_tags
}


########################################
### S3 Policy
########################################
resource "aws_s3_bucket_policy" "apply_policies" {
  for_each = module.s3.created_buckets

  bucket = each.key
  policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "terraform",
          Effect = "Allow",
          Principal = {
            AWS = sort([
              tostring(module.cloudfront.cloudfront_OAI)
            ])
          },
          Action   = "s3:GetObject",
          Resource = "${each.value.arn}/*"
        }
      ]
    }
  )

  depends_on = [
    module.s3
  ]
}
