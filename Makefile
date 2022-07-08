NIM_DOCKER := docker run -v $(shell pwd):/src nimlang/nim

NimExporter: src/NimExporter.nim NimExporter.nimble
	nimble build
