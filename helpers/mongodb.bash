#!/bin/bash

get_current_mongodb_storage_engine() {
  mongo --quiet --eval 'db.serverStatus().storageEngine.name'
}

get_current_mongodb_version() {
  mongo --quiet --eval 'db.version.split(".").splice(0, 2).join(".")'
}

is_storage_engine_wiredTiger() {
  [[ "wiredTiger" == "$(get_current_mongodb_storage_engine)" ]]
}
