#!/usr/bin/env python3

from time import sleep
import pika
import os

max_tries = 30
nb_tries = 1
port = int(os.getenv('MFBUS_RABBITMQ_AMQP_PORT'))

while nb_tries <= max_tries:
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters('localhost', port))
        channel = connection.channel()
        print("RabbitMQ Connection ok")
        exit(0)
    except Exception:
        print("RabbitMQ Connection Error, try %d, sleeping 1s" % nb_tries)
        nb_tries += 1
        if nb_tries == max_tries:
            print("RabbitMQ Connection Fails after %i tries" % max_tries)
            exit(1)
        sleep(1)
