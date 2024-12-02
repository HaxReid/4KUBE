#!/bin/bash

kubectl apply -f fleetman-mongodb.yaml
kubectl apply -f fleetman-queue.yaml
kubectl apply -f fleetman-position-simulator.yaml
kubectl apply -f fleetman-position-tracker.yaml
kubectl apply -f fleetman-api-gateway.yaml
kubectl apply -f fleetman-webapp.yaml
