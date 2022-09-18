#variables
variable "subnet_cidrs_public" {
  default = ["10.0.0.0/24", "10.1.0.0/24"]
  type = list
}
variable "subnet_cidrs_private" {
  default = ["10.2.0.0/24", "10.3.0.0/24"]
  type = list
}
variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}
data "aws_iam_role" "iam" {
  name = "AWSServiceRoleForECS"
}
#code
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc"
  }
}
resource "aws_subnet" "publicsubnets" {
  count = length(var.subnet_cidrs_public)
  vpc_id     = aws_vpc.vpc.id
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = "true"
  cidr_block = var.subnet_cidrs_public[count.index]
    tags = {
      Name = format("PublicpriyaFargate-%g",count.index)
   }
}
resource "aws_subnet" "private_subnet1" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[0]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_private[0]
    tags = {
        Name = format("PrivatePriyaFargate-%g",1)
    }
}
resource "aws_subnet" "private_subnet2" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[1]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_private[1]
    tags = {
        Name = format("PrivatePriyaFargate-%g",2)
    }
}
resource "aws_eip" "elasticip"{
  vpc = true
  depends_on = [aws_internet_gateway.priyaigw]
}
resource "aws_internet_gateway" "priyaigw" {
  vpc_id = aws_vpc.vpc.id
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.elasticip.id
  subnet_id = aws_subnet.publicsubnets[0].id
  
  tags = {
    Name = "Natgw"
  }
}
resource "aws_route_table" "publicRT1" {
    vpc_id = aws_vpc.vpc.id  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.priyaigw.id
    }
    tags = {
      Name = "PriyaPublicRoute"
    }
}
resource "aws_route_table" "privateRT2" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "PriyaRouteFargate"
  }
}
resource "aws_route_table_association" "RTA1" {
  count = length(var.subnet_cidrs_public)
  subnet_id      = element(aws_subnet.publicsubnets.*.id, count.index)
  route_table_id = aws_route_table.publicRT1.id
}
resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.privateRT2.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.privateRT2.id
}
resource "aws_security_group" "priya_security_group" {
  name        = "priya_security_group"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "priya_security_group"
  }
}
resource "aws_lb_target_group" "priya_target_group" {
  name     = "priya-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "aws_vpc.vpc.id"
  # Alter the destination of the health check to be the login page.
  health_check {    
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10    
    path                = "/"    
    port                = "80"  
  }
}
resource "aws_lb" "alb" {
  name            = "alb"
  security_groups = ["aws_security_group.priya_security_group.id"]
  subnets            = [for subnet in aws_subnet.publicsubnets : subnet.id]
  tags = {
    Name = "alb"
  }
}
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.priya_target_group.arn
  }
} 
#resource "aws_lb_listener_rule" "priya_listener_rule" {
  #listener_arn = "aws_lb_listener.lb_listener.arn"
  #priority = 100   
  #action {    
    #type             = "forward"    
    #target_group_arn = "aws_lb_target_group.priya_target_group.id"  
  #}   
  #condition {    
    #field  = "path-pattern"    
    #values = ["/api/*"]  
  #}
#}
resource "aws_ecr_repository" "priya-image"{
  name                 = "priyafargateecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecs_cluster" "sasi-cluster" {
  name = "PriyaFargateCluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_ecs_task_definition" "Priya_Task_Definition" {
  family = "ServiceforFargate"
  requires_compatibilities =  ["FARGATE"]
  cpu = "256"
  memory =  "512"
  network_mode =  "awsvpc"
  container_definitions  =  file("./ServiceforFargate.json")
  #jsonencode([
    #{
      #name      = "first"
      #image     = "service-first"
      #cpu       = 10
      #memory    = 512
    #  essential = true
     # portMappings = [
      #  {
       #   containerPort = 8080
        #  hostPort      = 8080
        #}
     # ])#
    #},
}
resource "aws_security_group" "ecs_tasks_security_group2" {
  name   = "ecs-tasks-security-group2"
  vpc_id = aws_vpc.vpc.id
 
  ingress {
   protocol         = "tcp"
   from_port        = 8080
   to_port          = 8080
   cidr_blocks      = ["0.0.0.0/0"]
  }
 
  egress {
   protocol         = "-1"
   from_port        = 0
   to_port          = 0
   cidr_blocks      = ["0.0.0.0/0"]
  }
}
resource "aws_ecs_service" "Priya_ecs_service" {
 name                               = "Priya-ecs-service"
 cluster                            = aws_ecs_cluster.sasi-cluster.id
 task_definition                    = aws_ecs_task_definition.Priya_Task_Definition.id
 desired_count                      = 2
 deployment_minimum_healthy_percent = 50
 deployment_maximum_percent         = 200
 launch_type                        = "FARGATE"
 scheduling_strategy                = "REPLICA"
 
 network_configuration {
   security_groups  = [aws_security_group.ecs_tasks_security_group2.id]
   subnets          = [aws_subnet.private_subnet1.id , aws_subnet.private_subnet2.id]
   assign_public_ip = false
 }
 
 load_balancer {
   target_group_arn = aws_lb_target_group.priya_target_group.arn
   container_name   = "PriyaFargateContainer"
   container_port   = 80
 }
}





