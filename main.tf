data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

module "blog_sg" {
  source              = "terraform-aws-modules/security-group/aws"
  version             = "5.3.0"
  vpc_id              = module.blog_vpc.vpc_id
  name                = "blog_new"  
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

# Auto Scalking Group
module "blog_asg" {
  source                  = "terraform-aws-modules/autoscaling/aws"
  version                 = "8.0.1"
  name                    = "blog"
  min_size                = 1
  max_size                = 2

  vpc_zone_identifier     = module.blog_vpc.public_subnets
  security_groups         = [module.blog_sg.security_group_id]

  image_id                = data.aws_ami.app_ami.id
  instance_type           = var.instance_type

}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  
  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}



# Application Load Balancer
module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name                = "blog-alb"
  internal            = false
  load_balancer_type  = "application"


  vpc_id              = module.blog_vpc.vpc_id
  subnets             = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  enable_deletion_protection = false

  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}

# Target Group
resource "aws_lb_target_group" "blog_alb_tg" {
  name     = "blog-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
  target_type = "instance"
}

# ALB Listener
resource "aws_lb_listener" "example" {
  load_balancer_arn = module.blog_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blog_alb_tg.arn
  }
}