Worker      = require '../src/worker'
MeshbluAmqp = require 'meshblu-amqp'
RedisNS     = require '@octoblu/redis-ns'
Redis       = require 'ioredis'
{ JobManagerResponder } = require 'meshblu-core-job-manager'
async       = require 'async'
UUID        = require 'uuid'
{ JobManagerResponder }  = require 'meshblu-core-job-manager'

describe 'whoami', ->
  beforeEach 'constants', ->
    queueId = UUID.v4()
    @redisUri = 'redis://localhost:6379'
    @namespace = 'ns'
    @requestQueueName = "test:request:queue:#{queueId}"
    @responseQueueName = "test:response:queue:#{queueId}"
    @namespace = 'ns'
    @redisUri = 'redis://localhost'

  beforeEach 'new job manager', (done) ->
    @workerFunc = sinon.stub()
    @jobManager = new JobManagerResponder {
      @redisUri
      @namespace
      maxConnections: 1
      jobTimeoutSeconds: 1
      queueTimeoutSeconds: 1
      jobLogSampleRate: 0
      @requestQueueName
      @responseQueueName
      @workerFunc
    }

    @jobManager.start done

  afterEach (done) ->
    @jobManager.stop done

  beforeEach 'new worker', (done) ->
    @worker = new Worker {
      @redisUri
      @requestQueueName
      @responseQueueName
      @namespace
      amqpUri: 'amqp://meshblu:judgementday@127.0.0.1'
      jobTimeoutSeconds: 1
      jobLogRedisUri: @redisUri
      jobLogQueue: 'sample-rate:0.00'
      jobLogSampleRate: 0
      redisUri: @redisUri
      cacheRedisUri: @redisUri
      namespace: @namespace
      @requestQueueName
      @responseQueueName
    }

    @worker.run done
    return # stupid promises

  afterEach (done) ->
    @worker.stop done
    return # nothing

  afterEach (done) ->
    @jobManager.stop done

  beforeEach 'create client', (done) ->
    @client = new MeshbluAmqp uuid: 'some-uuid', token: 'some-token', hostname: 'localhost'
    @client.connect done
    return # avoid returning async

  beforeEach 'when whoami is called', (done) ->
    response =
      metadata:
        data: { whoami:'somebody' }
        code: 200
      data: { whoami:'somebody' }

    @workerFunc.yields null, response

    @client.whoami (error, @data) => done(error)
    return # stupid promises

  it 'should create a GetDevice job', ->
    expect(@workerFunc).to.have.been.called
    request = @workerFunc.firstCall.args[0]
    expect(request.metadata.jobType).to.deep.equal 'GetDevice'

  it 'should give us a device', ->
    expect(@data).to.deep.equal {whoami: 'somebody'}
