{ Client } = require 'amqp10'
Promise    = require 'bluebird'
debug      = require('debug')('meshblu-core-worker-amqp:worker')
Redis      = require 'ioredis'
RedisNS     = require '@octoblu/redis-ns'
JobLogger  = require 'job-logger'
{ JobManagerRequester } = require 'meshblu-core-job-manager'

class Worker
  constructor: (options)->
    {
      @jobTimeoutSeconds
      @jobLogQueue
      @jobLogRedisUri
      @jobLogSampleRate
      @amqpUri
      @maxConnections
      @cacheRedisUri
      @redisUri
      @namespace
      @requestQueueName
      @responseQueueName
    } = options

  connect: (callback) =>
    options =
      reconnect:
        forever: false
        retries: 0

    @client = new Client options
    @client.connect @amqpUri
      .then =>
        @client.once 'connection:closed', =>
          throw new Error 'connection to amqp server lost'
        Promise.all [
          @client.createSender()
          @client.createReceiver('meshblu.request')
        ]
      .spread (@sender, @receiver) =>
        callback()
        return true # promises are dumb
      .catch (error) =>
        callback error
      .error (error) =>
        callback error

  run: (callback) =>
    @connect (error) =>
      return callback error if error?

      client = new RedisNS @namespace, new Redis @redisUri, dropBufferSupport: true
      queueClient = new RedisNS @namespace, new Redis @redisUri, dropBufferSupport: true

      jobLogger = new JobLogger
        client: new Redis @jobLogRedisUri, dropBufferSupport: true
        indexPrefix: 'metric:meshblu-core-protocol-adapter-amqp'
        type: 'meshblu-core-protocol-adapter-amqp:request'
        jobLogQueue: @jobLogQueue

      @jobManager = new JobManagerRequester {
        client
        queueClient
        @jobTimeoutSeconds
        @jobLogSampleRate
        @requestQueueName
        @responseQueueName
        queueTimeoutSeconds: @jobTimeoutSeconds
      }

      @jobManager._do = @jobManager.do
      @jobManager.do = (request, callback) =>
        @jobManager._do request, (error, response) =>
          jobLogger.log { error, request, response }, (jobLoggerError) =>
            return callback jobLoggerError if jobLoggerError?
            callback error, response

      queueClient.on 'ready', =>
        @jobManager.startProcessing()

      @receiver.on 'message', (message) =>
        debug 'message received:', message
        job = @_amqpToJobManager message
        debug 'job:', job

        @jobManager.do job, (error, response) =>
          return if error?
          debug 'response received:', response

          options =
            properties:
              correlationId: message.properties.correlationId
              subject: message.properties.replyTo
            applicationProperties:
              code: response.code || 0

          debug 'sender options', options
          @sender.send response.rawData, options

  stop: (callback) =>
    @jobManager?.stopProcessing()
    @client.disconnect()
      .then callback
      .catch callback

  _amqpToJobManager: (message) =>
    job =
      metadata: message.applicationProperties
      rawData: message.body

module.exports = Worker
