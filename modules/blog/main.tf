data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
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

# Auto Scaling Group
resource "aws_autoscaling_group" "blog_asg" {
  name                    = "blog-asg"
  min_size                = var.asg_min_size
  max_size                = var.asg_max_size

  vpc_zone_identifier     = module.blog_vpc.public_subnets

  target_group_arns = [aws_lb_target_group.blog_alb_tg.arn]

  launch_template {
    id = aws_launch_template.as_conf.id
  }

}

resource "aws_launch_template" "as_conf" {
  name_prefix   = "terraform-lc-example-"
  image_id      = data.aws_ami.app_ami.id
  instance_type = "t2.micro"
  

  lifecycle {
    create_before_destroy = true
  }
}


module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  
  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}

resource "aws_lb" "blog-alb" {
  name = "blog-alb"
  internal = false
  load_balancer_type = "application"

  subnets             = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  enable_deletion_protection = false

    tags = {
    Environment = var.environment.name
    Project     = "Example"
  }
}

# Target Group
resource "aws_lb_target_group" "blog_alb_tg" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
  target_type = "instance"
}

# ALB Listener
resource "aws_lb_listener" "blog-alb-listener" {
  load_balancer_arn = aws_lb.blog-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blog_alb_tg.arn
  }
}