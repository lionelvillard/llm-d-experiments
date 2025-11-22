#!/bin/bash


for i in {1..10000}; do
    #echo sending request "${i}"

    curl -s localhost:8000/granite3/v1/chat/completions -H "Content-Type: application/json" -d '{
                    "model": "granite/granite-3-2-8b-instruct",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }' &

    sleep 0.0001
done
