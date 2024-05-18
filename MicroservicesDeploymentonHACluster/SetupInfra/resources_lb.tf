resource "aws_lb_target_group" "ha-k8s-tg" {
  name     = "ha-k8s-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.ha-k8s-vpc.id
}

resource "aws_lb" "ha-k8s-lb" {
  name = "ha-k8s-alb"
  subnets = aws_subnet.ha-k8s-subnets.*.id
  //security_groups = aws_security_group.mysg_lb[*].id
  internal = false
  load_balancer_type = "network"
  count = 1
  depends_on = [ aws_vpc.ha-k8s-vpc ]
}

resource "aws_lb_listener" "ha-k8s-listener" {
    load_balancer_arn = "${aws_lb.ha-k8s-lb[0].arn}"
    port = "6443"
    protocol = "TCP"
    default_action {
        type = "forward"
        target_group_arn = "${aws_lb_target_group.ha-k8s-tg.arn}"
        
    }
    count=1
    depends_on = [ aws_lb.ha-k8s-lb]
}

resource "aws_lb_listener" "ha-k8s-listener-vote" {
    load_balancer_arn = "${aws_lb.ha-k8s-lb[0].arn}"
    port = "31001"
    protocol = "TCP"
    default_action {
        type = "forward"
        target_group_arn = "${aws_lb_target_group.ha-k8s-tg.arn}"
        
    }
    count=1
    depends_on = [ aws_lb.ha-k8s-lb]
}

resource "aws_lb_listener" "ha-k8s-listener-result" {
    load_balancer_arn = "${aws_lb.ha-k8s-lb[0].arn}"
    port = "31000"
    protocol = "TCP"
    default_action {
        type = "forward"
        target_group_arn = "${aws_lb_target_group.ha-k8s-tg.arn}"
        
    }
    count=1
    depends_on = [ aws_lb.ha-k8s-lb]
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.ha-k8s-tg.arn
  target_id        = aws_instance.h8-k8s-master[count.index].id
  port             = 6443
  count = 3 
  depends_on = [ aws_instance.h8-k8s-master ]
}

/* resource "aws_lb_listener_rule" "kubernetes_listener_rule" {
  listener_arn = aws_lb_listener.ha-k8s-listener[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ha-k8s-tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
} */