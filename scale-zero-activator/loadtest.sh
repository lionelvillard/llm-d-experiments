#!/bin/bash


for i in {1..5}; do
    echo sending request ${i}

    curl -s localhost:8080/granite3/v1/chat/completions -H "Content-Type: application/json" -d '{
                    "model": "granite/granite3-8B",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'

    sleep 0.1
done
