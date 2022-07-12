# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.
import std/strformat, std/uri, strutils, tables
import os, system, times, json, logging
import asynchttpserver, asyncdispatch, httpclient


const port = 8082
var
  server = newAsyncHttpServer()
  iteration = 0
  stats {.threadvar.}: Table[string, int]
  PROMETHEUS {.threadvar.}: string


proc cb(req: Request) {.async, gcsafe.} =
  if req.url.path == "/health":
    if stats["now"] > 0:
      await req.respond(Http200, "Ok")
    else:
      await req.respond(HttpCode(500), "nok")
    return
  var resp = [
    "up 1",
    &"""revenue{{time="now"}} {stats["now"]}""",
    &"""revenue{{time="prev"}} {stats["prev"]}""",
    &"""revenue{{time="prev_prev"}} {stats["prev_prev"]}""",
  ].join("\n")
  info(&"""Return stats: {stats["now"]}/{stats["prev"]}/{stats["prev_prev"]}""")
  await req.respond(Http200, resp, newHttpHeaders([("Content-Type", "text/plain")]))


proc getValues(endTS: DateTime, name: string) {.async.} =
  let cli = newAsyncHttpClient()
  defer: cli.close()
  var uri = &"http://{PROMETHEUS}/api/v1/query"
  let query = encodeQuery({"time": $(endTS),
                            "query": "max by(namespace) (monthly_all{namespace=\"octo-prod\"})"})
  uri = &"{uri}?{query}"
  debug(&"Get on: {uri}")
  let resp = await cli.get(uri)
  let body = await resp.body
  debug(&"get body: {resp.status[0..2]=}")
  debug(&"{body}")
  let jsonData = parseJson(body)
  stats[name] = jsonData["data"]["result"][0]["value"][1].getStr.parseInt


proc updateLoop() {.async.} =
  while true:
    iteration += 1
    try:
      await all(
        [
          getValues(now().utc, "now"),
          getValues(now().utc - 1.months, "prev"),
          getValues(now().utc - 2.months, "prev_prev"),
        ]
      )
    except:
      let msg = getCurrentExceptionMsg()
      error(&"Exception: {msg}")
      discard
    await sleepAsync(3000)


when isMainModule:
  let consoleLogger = newConsoleLogger()
  addHandler(consoleLogger)
  setLogFilter(lvlInfo)
  stats = {"now": 0, "prev": 0, "prev_prev": 0}.toTable

  PROMETHEUS = getEnv("PROMETHEUS", "")
  if PROMETHEUS.len() == 0:
    error("Please specify PROMETHEUS variable")
    quit(1)
  discard updateLoop()
  info(&"Listen 0.0.0.0:{port}")
  waitFor server.serve(Port(port), cb)
