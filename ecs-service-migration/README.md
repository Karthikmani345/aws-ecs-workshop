# AWS ECS Fargate Task Migration Script

## Description

This shell script automates the migration of AWS ECS Fargate tasks and services from one cluster to another within the same region. The script performs the following tasks:

1. Moves the Fargate tasks from the source cluster to the destination cluster, utilizing Fargate Spot for cost optimization.
2. Creates a service in the destination cluster with the same configuration as the source service.
3. Monitors the health status of the new tasks in the destination cluster and waits for them to become healthy.
4. Deletes the service from the old cluster once all new tasks are healthy in the destination cluster.

## Diagram

```
          +----------------------------------------+
          |            Source Cluster              |
          |                                        |
          |   +---------------------+              |
          |   |      ECS Service    |              |
          |   +---------------------+              |
          |       |               |                |
          |       v               |                |
          |   +---------------------+              |
          |   |   Fargate Tasks    |              |
          |   +---------------------+              |
          |                                        |
          +----------------------------------------+

          +----------------------------------------+
          |          Destination Cluster           |
          |                                        |
          |   +---------------------+              |
          |   |      ECS Service    |              |
          |   +---------------------+              |
          |       |               |                |
          |       v               |                |
          |   +---------------------+              |
          |   |   Fargate Tasks    |              |
          |   +---------------------+              |
          |                                        |
          +----------------------------------------+
```

## Usage

1. Set the necessary variables in the script:

   - `SERVICE_NAME`: The name of the ECS service to be migrated.
   - `SOURCE_CLUSTER`: The name of the source cluster from which the service will be migrated.
   - `DEST_CLUSTER`: The name of the destination cluster to which the service will be migrated.

2. Ensure that you have the AWS CLI installed and configured with appropriate permissions to access the source and destination ECS clusters.

3. Run the script:
   ```bash
   bash ecs-service-migration.sh
   ```

## Notes

- The script uses AWS CLI commands and `jq` for JSON parsing, so make sure you have them installed and configured correctly.
- The script will wait for the service to become active in the destination cluster and monitor the health of the new tasks before deleting the service from the source cluster.
- If any new tasks in the destination cluster are not healthy, the script will retry until they become healthy or reach the maximum number of attempts (`MAX_TRIES` in the script).
- The script will print relevant status messages to keep you informed about the migration progress and the outcome.

Please ensure that you review and verify the variables and settings in the script before running it to avoid any unintended changes to your AWS ECS infrastructure.
