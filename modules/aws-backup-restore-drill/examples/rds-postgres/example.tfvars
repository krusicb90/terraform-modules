# Placeholder values. Replace every one of them with your own.
region                       = "eu-central-1"
db_instance_arn              = "arn:aws:rds:eu-central-1:111122223333:db:orders"
vpc_id                       = "vpc-00000000000000000"
restore_db_subnet_group_name = "restore-test"
validator_subnet_ids         = ["subnet-00000000000000000", "subnet-11111111111111111"]
credentials_secret_arn       = "arn:aws:secretsmanager:eu-central-1:111122223333:secret:orders-db-AbCdEf"
pg8000_layer_arn             = "arn:aws:lambda:eu-central-1:111122223333:layer:restore-drill-driver:1"
alerts_topic_arn             = "arn:aws:sns:eu-central-1:111122223333:alerts"
