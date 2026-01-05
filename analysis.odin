package mylsp

import "core:fmt"
import "core:strings"
import "core:log"
import "core:mem"

State :: struct {
  documents: map[string]string,
  allocator: mem.Allocator,
}

state_hover :: proc(state: ^State, request: HoverRequest, allocator := context.allocator) -> HoverResponse {
  context.allocator = allocator

  uri := request.params.textDocument.uri
  position := request.params.position

  document := state.documents[uri]

  response := HoverResponse {
    jsonrpc = "2.0",
    id = request.id,
    result = {
      contents = fmt.aprintf("File: %s, Characters: %d", uri, len(document))
    }
  }

  return response
}

state_definition :: proc(state: ^State, request: DefinitionRequest, allocator := context.allocator) -> DefinitionResponse {
  context.allocator = allocator

  uri := request.params.textDocument.uri
  position := request.params.position

  document := state.documents[uri]

  response := DefinitionResponse {
    jsonrpc = "2.0",
    id = request.id,
    result = {
      uri = uri,
      range = { 
        start = { line = position.line - 1, character = 0 },
        end = { line = position.line - 1, character = 0 },
      }
    }
  }

  return response
}

state_code_action :: proc(state: ^State, request: CodeActionRequest, allocator := context.allocator) -> CodeActionResponse {
  context.allocator = allocator

  uri := request.params.textDocument.uri
  text := state.documents[uri]

  actions := make([dynamic]CodeAction, 0, 2)
  row: uint = 0
  for line in strings.split_lines_iterator(&text) {
    defer row += 1

    if row != request.params.range.start.line {
      continue
    }

    idx := strings.index(line, BAD_WORD)
    if idx >= 0 {
      replaceChange: map[string][]TextEdit
      replaceChange[uri] = make([]TextEdit, 1)
      replaceChange[uri][0] = {
        range = { 
          start = { row, cast(uint)idx }, 
          end = { row, cast(uint)idx + len(BAD_WORD) },
        },
        newText = "Neovim",
      }

      append(&actions, CodeAction {
        title = "Replace VS C*de with superior editor",
        edit = { changes = replaceChange }
      })


      censorChange: map[string][]TextEdit
      censorChange[uri] = make([]TextEdit, 1)
      censorChange[uri][0] = {
        range = { 
          start = { row, cast(uint)idx }, 
          end = { row, cast(uint)idx + len(BAD_WORD) },
        },
        newText = "VS C*de",
      }

      append(&actions, CodeAction {
        title = "Censor to VS C*de",
        edit = { changes = censorChange }
      })
    }
  }

  response := CodeActionResponse {
    jsonrpc = "2.0",
    id = request.id,
    result = actions[:],
  }

  return response
}

state_completion :: proc(state: ^State, request: CompletionRequest, allocator := context.allocator) -> CompletionResponse {
  context.allocator = allocator

  uri := request.params.textDocument.uri
  text := state.documents[uri]

  items := make([dynamic]CompletionItem, 0, 1)
  append(&items, CompletionItem { 
    label = "Neovim (BTW)", 
    detail = "Very cool editor", 
    documentation = "Example documentation",
  })

  response := CompletionResponse {
    jsonrpc = "2.0",
    id = request.id,
    result = items[:],
  }

  return response
}
