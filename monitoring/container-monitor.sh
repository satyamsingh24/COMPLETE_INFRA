#!/bin/bash

SNS_TOPIC_ARN="arn:aws:sns:ap-south-1:176583374037:complete-infra-alerts"
AWS_REGION="ap-south-1"
CONTAINERS=("backend" "mysql" "redis" "nginx" "grafana" "prometheus")

for container in "${CONTAINERS[@]}"; do
  STATUS=$(docker inspect --format='{{.State.Status}}' $container 2>/dev/null)
  HEALTH=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null)

  if [ "$STATUS" != "running" ]; then
    MESSAGE="🚨 ALERT: Container '$container' is DOWN on EC2!
Status: $STATUS
Time: $(date)
Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
Action Required: Please check immediately!"

    aws sns publish \
      --topic-arn $SNS_TOPIC_ARN \
      --subject "🚨 Container DOWN: $container" \
      --message "$MESSAGE" \
      --region $AWS_REGION

    echo "Alert sent for $container"
  elif [ "$HEALTH" = "unhealthy" ]; then
    MESSAGE="⚠️ WARNING: Container '$container' is UNHEALTHY on EC2!
Health: $HEALTH
Time: $(date)
Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

    aws sns publish \
      --topic-arn $SNS_TOPIC_ARN \
      --subject "⚠️ Container UNHEALTHY: $container" \
      --message "$MESSAGE" \
      --region $AWS_REGION

    echo "Warning sent for $container"
  fi
done
