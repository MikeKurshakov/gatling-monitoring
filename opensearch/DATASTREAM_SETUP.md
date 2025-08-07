# OpenSearch Data Stream Setup Guide

This guide describes the data stream setup for performance metrics in OpenSearch.

## Overview

Performance metrics are divided into three separate data streams:

1. **performance-metrics-requests**: Contains request-level metrics (duration, result status, errors)
2. **performance-metrics-tests**: Contains test lifecycle events (start/end)
3. **performance-metrics-users**: Contains active user counts per scenario

Each data stream uses a consistent naming convention and field mappings optimized for its data type.

## Templates and Mappings

### ISM Policy

A single Index State Management (ISM) policy is defined for all data streams with four states:

- **Hot State (0-30 days)**: Active indices receiving new data
- **Warm State (30-120 days)**: Less frequently accessed data, force merged to 1 segment
- **Cold State (120-730 days)**: Rarely accessed data with optimized storage, read-only
- **Delete State (after 730 days)**: Data is removed

### Data Stream Templates

Each data stream has its own template with specific field mappings:

- **Requests Template**: Optimized for request-level metrics with fields for duration, result, and error messages
- **Tests Template**: Optimized for test lifecycle events with fields for action and description
- **Users Template**: Optimized for active user metrics with fields for active count and scenario

## Common Fields

All data streams share these common fields for correlation:

- `@timestamp`: The main timestamp for the event
- `@relativeTimestamp`: Relative time from test start
- `runId`: Unique identifier for a test run
- `testEnvironment`: Environment where test was executed
- `systemUnderTest`: System being tested
- `runName`: Name of the test run
- `host`: Host machine identifier
- `nodeName`: Node identifier

## Logstash Pipeline

The Logstash pipeline automatically routes events to the appropriate data stream based on their content:

- Events with a `name` field -> requests data stream
- Events with an `action` field -> tests data stream
- Events with a `scenario` field -> users data stream

## Setup Instructions

1. **Create the ISM Policy**:
   ```
   PUT _plugins/_ism/policies/performance-metrics-policy
   {content of performance-metrics-ism-policy.json}
   ```

2. **Create Index Templates**:
   ```
   PUT _index_template/performance-metrics-requests
   {content of performance-metrics-requests-template.json}
   
   PUT _index_template/performance-metrics-tests
   {content of performance-metrics-tests-template.json}
   
   PUT _index_template/performance-metrics-users
   {content of performance-metrics-users-template.json}
   ```

3. **Create Data Streams**:
   ```
   PUT _data_stream/performance-metrics-requests
   PUT _data_stream/performance-metrics-tests
   PUT _data_stream/performance-metrics-users
   ```

4. **Configure Logstash**:
   Update your Logstash pipeline configuration to use the new `kafka_to_datastream.conf` file.

## Querying Data

To query data across streams:

```
GET performance-metrics-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "runId": 123456 } },
        { "range": { "@timestamp": { "gte": "now-1d", "lte": "now" } } }
      ]
    }
  }
}
```

For specific stream queries:

```
GET performance-metrics-requests/_search
{
  "query": {
    "term": { "result": "KO" }
  }
}
```

## Maintenance

- Monitor shard sizes and adjust the ISM policy as needed
- Review field mappings if new fields are added to the data
- Consider using cross-cluster replication for disaster recovery