#!/bin/bash

set -e  # Exit immediately if any command exits with a non-zero status


# Set your variables
SERVICE_NAME=
SOURCE_CLUSTER=
DEST_CLUSTER=

echo "################ ECS Migration Started ################" 
echo "Migrating Service : $SERVICE_NAME | Source Cluster : $SOURCE_CLUSTER | Destination Cluster : $DEST_CLUSTER"

# Describe the service to get the current configuration
SERVICE_DESCRIBE=$(aws ecs describe-services --cluster $SOURCE_CLUSTER --services $SERVICE_NAME)

# Get the current task definition, load balancer, deployment configuration, and desired count
TASK_DEF=$(echo $SERVICE_DESCRIBE | jq -r '.services[0].taskDefinition')
LOAD_BALANCER=$(echo $SERVICE_DESCRIBE | jq '.services[0].loadBalancers[0]')
DESIRED_COUNT=$(echo $SERVICE_DESCRIBE | jq -r '.services[0].desiredCount')
DEPLOYMENT_CONFIG=$(echo $SERVICE_DESCRIBE | jq '.services[0].deploymentConfiguration | .deploymentCircuitBreaker.enable=true')

# Get network configuration details
NETWORK_CONFIG=$(echo $SERVICE_DESCRIBE | jq '.services[0].networkConfiguration')

# Get Target Group ARN
TARGET_GROUP_ARN=$(echo $LOAD_BALANCER | jq -r '.targetGroupArn')

# Get the list of task IDs before creating the service
TASK_IDS_BEFORE=$(aws ecs list-tasks --cluster $DEST_CLUSTER --service-name $SERVICE_NAME | jq -r '.taskArns[]' | cut -d "/" -f3)


# Create a service in the destination cluster using the same configuration
aws ecs create-service \
  --cluster $DEST_CLUSTER \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_DEF \
  --desired-count $DESIRED_COUNT \
  --load-balancers "$LOAD_BALANCER" \
  --network-configuration "$NETWORK_CONFIG" \
  --deployment-configuration "$DEPLOYMENT_CONFIG"

# Check the status of the service every 20 seconds
echo "Waiting for the service to start..."
TRIES=0
MAX_TRIES=15

while [[ $TRIES -lt $MAX_TRIES ]]; do
    SERVICE_STATUS=$(aws ecs describe-services --cluster $DEST_CLUSTER --services $SERVICE_NAME | jq -r '.services[0].status')

    if [[ $SERVICE_STATUS == "ACTIVE" ]]; then
        # If the service is active, list the tasks and get their IDs
        TASK_IDS_AFTER=$(aws ecs list-tasks --cluster $DEST_CLUSTER --service-name $SERVICE_NAME | jq -r '.taskArns[]' | cut -d "/" -f3)

        # Save the sorted list of task IDs to temporary files
        echo "$TASK_IDS_BEFORE" | sort > task_ids_before.txt

        # Save the sorted list of task IDs to temporary files        
        echo "$TASK_IDS_AFTER" | sort > task_ids_after.txt

        # Find the new tasks by comparing the before and after lists
        NEW_TASK_IDS=$(comm -13 task_ids_before.txt task_ids_after.txt)

        # Remove the temporary files
        rm task_ids_before.txt task_ids_after.txt

        echo New ECS Task Ids  $NEW_TASK_IDS
        TASK_HEALTH=""

        # Check the health status of each new task in the target group
        for TASK_ID in $NEW_TASK_IDS; do
            ENI_ID=$(aws ecs describe-tasks --cluster $DEST_CLUSTER --tasks $TASK_ID --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' --output text)

            echo TASK_ID: $TASK_ID
            echo ENI_ID: $ENI_ID

            # Get all TargetHealthDescriptions for the specified target group
            TARGET_HEALTH_DESCR=$(aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN)

            # echo "TARGET_HEALTH_DESCR" $TARGET_HEALTH_DESCR

            # Extract the object with matching Target.Id value
            MATCHING_TARGET=$(echo "$TARGET_HEALTH_DESCR" | jq -r '.TargetHealthDescriptions[] | select(.Target.Id == "'"$ENI_ID"'")')

            # Check if a matching object was found
            if [[ -n $MATCHING_TARGET ]]; then
                TARGET_ID=$(echo "$MATCHING_TARGET" | jq -r '.Target.Id')
                TARGET_HEALTH=$(echo "$MATCHING_TARGET" | jq -r '.TargetHealth.State')

                echo "Target Group IP: $TARGET_ID"
                echo "Target Group health: $TARGET_HEALTH"

                TASK_HEALTH=$TARGET_HEALTH
            else
                echo "No matching target found."
                break
            fi

            if [[ $TASK_HEALTH != "healthy" ]]; then
                # If any new task is not healthy, retry
                echo "One or more new tasks are not healthy. Retrying in 15 seconds..."
                break
            fi
        done

        # If all new tasks are healthy, delete the old service and exit
        if [[ $TASK_HEALTH == "healthy" ]]; then
            echo "All new tasks are healthy. Deleting the service from the old cluster."
            aws ecs delete-service --cluster $SOURCE_CLUSTER --service $SERVICE_NAME --force
            echo "Deleted the service from the source - Cluster $SOURCE_CLUSTER | Service $SERVICE_NAME"
            echo "################ ECS Migration Completed ################"
            exit 0
        fi
    else
        echo "Service not active yet. Retrying in 15 seconds..."
    fi
    let TRIES=TRIES+1
    sleep 15
done

echo "The service is not active or one or more new tasks are not healthy after $MAX_TRIES tries. Deleting the service from the new cluster."
aws ecs delete-service --cluster $DEST_CLUSTER --service $SERVICE_NAME --force

echo "Deleted the service from the destination - Cluster $DEST_CLUSTER | Service $SERVICE_NAME" 
echo "################ ECS Migration Completed ################"
exit 0
