_      = require 'lodash'
Worker = require './src/worker'
UUID   = require 'uuid'

class Command
  constructor: ->
    @options =
      amqpUri:                process.env.AMQP_URI
      cacheRedisUri:          process.env.CACHE_REDIS_URI || process.env.REDIS_URI
      jobLogQueue:            process.env.JOB_LOG_QUEUE || 'sample-rate:1.00'
      jobLogRedisUri:         process.env.JOB_LOG_REDIS_URI || process.env.REDIS_URI
      jobLogSampleRate:       parseFloat(process.env.JOB_LOG_SAMPLE_RATE || 0)
      jobTimeoutSeconds:      parseInt(process.env.JOB_TIMEOUT_SECONDS || 30)
      maxConnections:         parseInt(process.env.CONNECTION_POOL_MAX_CONNECTIONS || 100)
      namespace:              process.env.NAMESPACE || 'meshblu'
      requestQueueName     :  process.env.REQUEST_QUEUE_NAME || 'v2:request:queue'
      responseQueueBaseName:  process.env.RESPONSE_QUEUE_BASE_NAME || 'v2:response:queue'
      redisUri:               process.env.REDIS_URI

  panic: (error) =>
    console.error error.stack
    process.exit 1

  run: =>
    @panic new Error('Missing required environment variable: AMQP_URI') if _.isEmpty @options.amqpUri
    @panic new Error('Missing required environment variable: REDIS_URI') if _.isEmpty @options.redisUri
    @panic new Error('Missing required environment variable: CACHE_REDIS_URI') if _.isEmpty @options.cacheRedisUri
    @panic new Error('Missing required environment variable: JOB_LOG_REDIS_URI') if _.isEmpty @options.jobLogRedisUri
    @panic new Error('Missing required environment variable: JOB_LOG_QUEUE') if _.isEmpty @options.jobLogQueue
    @panic new Error('Missing required environment variable: JOB_LOG_SAMPLE_RATE') unless _.isNumber @options.jobLogSampleRate
    @panic new Error('Missing environment variable: REQUEST_QUEUE_NAME') if _.isEmpty @options.requestQueueName
    @panic new Error('Missing environment variable: RESPONSE_QUEUE_BASE_NAME') if _.isEmpty @options.responseQueueBaseName

    responseQueueId = UUID.v4()
    @options.responseQueueName = "#{@options.responseQueueBaseName}:#{responseQueueId}"
    worker = new Worker @options

    console.log 'AMQP worker is working'

    worker.run (error) =>
      return @panic error if error?

    process.on 'SIGTERM', =>
      console.log 'SIGTERM caught, exiting'
      worker.stop =>
        process.exit 0

command = new Command()
command.run()
