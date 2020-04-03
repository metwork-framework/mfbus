#!/usr/bin/env python3

from time import sleep
import pika
import os

max_tries = 10
nb_tries = 1
port = int(os.getenv('MFBUS_RABBITMQ_AMQP_PORT'))

while nb_tries <= max_tries:
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters('localhost', port))
        channel = connection.channel()
        print(" Connection ok")
        break
    except Exception as e:
        print(" Connection Error, try %d" % nb_tries)
        nb_tries += 1
        if nb_tries == max_tries:
            print(" No more tries ==> exit")
            exit(1)
        sleep(1)

channel.queue_declare(queue='hello')
channel.basic_publish(exchange='',
                      routing_key='hello',
                      body='Hello World!')
print(" [x] Sent 'Hello World!'")
connection.close()
