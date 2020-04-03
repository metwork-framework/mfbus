#!/usr/bin/env python3

import pika
import os
port = int(os.getenv('MFBUS_RABBITMQ_AMQP_PORT'))

connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', port))
channel = connection.channel()
channel.queue_declare(queue='hello')


def callback(ch, method, properties, body):
    print(" [x] Received %r" % body)
    exit(0)


channel.basic_consume(
    queue='hello', on_message_callback=callback, auto_ack=True)


print(' [*] Waiting for messages. To exit press CTRL+C')
channel.start_consuming()
