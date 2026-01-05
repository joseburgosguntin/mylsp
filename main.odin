package mylsp

import "core:encoding/json"
import "core:log"
import "core:fmt"
import "core:bytes"
import "core:testing"
import "core:strconv"
import "core:bufio"
import "core:io"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:mem"

LOGGER_OPTIONS: log.Options : {
	.Level,
	.Line,
	.Short_File_Path,
}

BAD_WORD :: "VS Code"
GOOD_WORD :: "Neovim"

split :: proc(data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
  msg := data

  header_separator_str := "\r\n\r\n"
  header_separator := transmute([]byte)header_separator_str

  headers, headers_ok := bytes.split_iterator(&msg, header_separator)
  if !headers_ok {
    return 0, nil, nil, false
  }

  content_length_str := cast(string)headers[len("Content-Length: "):]
  content_length, content_length_ok := strconv.parse_int(content_length_str)
  if !content_length_ok {
    return 0, nil, .Too_Short, false
  }

  body, body_ok := bytes.split_iterator(&msg, header_separator)
  if len(body) < content_length {
    return 0, nil, nil, false
  }

  total_length := len(headers) + len(header_separator) + content_length
  return total_length, data[:total_length], nil, false
}

main :: proc() {
  log_file, log_file_err := os.open("./log.txt", os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o666)
  assert(log_file_err == nil)
	logger := log.create_file_logger(log_file, .Debug, LOGGER_OPTIONS)
	defer log.destroy_console_logger(logger)
	context.logger = logger

  log.info("Starting: mylsp")

  state: State
  state.allocator = context.allocator
  state.documents = make(map[string]string, state.allocator)

  scanner: bufio.Scanner
  bufio.scanner_init(&scanner, os2.stdin.stream)
  scanner.split = split

  b: bufio.Writer
  bufio.writer_init(&b, os2.stdout.stream)
  w := bufio.writer_to_writer(&b)

  tracking: mem.Tracking_Allocator
  mem.tracking_allocator_init(&tracking, context.allocator)
  context.allocator = mem.tracking_allocator(&tracking)
  
  for bufio.scanner_scan(&scanner) {
    defer free_all(context.temp_allocator)
    msg := bufio.scanner_bytes(&scanner)
    method, contents := decode_message(msg, context.temp_allocator)

    handle_message(w, &state, method, contents, context.temp_allocator)

    flush_err := bufio.writer_flush(&b)
    assert(flush_err == nil)
    for a, b in tracking.allocation_map {
      log.error(b)
    }
  }
}

handle_message :: proc(
  w: io.Writer, 
  state: ^State, 
  method: string, 
  contents: []byte, 
  allocator := context.temp_allocator
) {
  context.allocator = allocator

  log.info(method, transmute(string)contents)
  switch method {
  case "initialize":
    request: InitializeRequest
    err := json.unmarshal(contents, &request)
    assert(err == nil)
    log.info(request)

    clientInfo := request.params.clientInfo
    log.infof("Connected to %s %s", clientInfo.name, clientInfo.version)

    response := InitializeResponse {
      jsonrpc = "2.0",
      id = request.id,
      result = {
        capabilities = {
          textDocumentSync = .Full,
          hoverProvider = true,
          definitionProvider = true,
          codeActionProvider = true,
          completionProvider = map[string]any {},
        },
        serverInfo = { "mylsp", "0.0.0-beta1.final" },
      }
    }
    write_message(w, response)
  case "initialized":
  case "textDocument/didOpen":
    request: DidOpenTextDocumentNotification
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    textDocument := request.params.textDocument
    log.infof("Opened: %s `%s`", textDocument.uri, textDocument.text)
    assert(textDocument.uri not_in state.documents)
    state.documents[strings.clone(textDocument.uri, state.allocator)] = strings.clone(textDocument.text, state.allocator)

    diagnostics := diagnostics_for_file(textDocument.text)
    notification := PublishDiagnosticsNotification {
      jsonrpc = "2.0",
      method = "textDocument/publishDiagnostics",
      params = {
        uri = request.params.textDocument.uri,
        diagnostics = diagnostics,
      }
    }
    write_message(w, notification)

  case "textDocument/didChange":
    request: DidChangeTextDocumentNotification
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    textDocument := request.params.textDocument
    contentChanges := request.params.contentChanges
    log.infof("Changed: %s `%v`", textDocument.uri, contentChanges)
    for change in contentChanges {
      delete(state.documents[textDocument.uri], state.allocator)
      state.documents[strings.clone(textDocument.uri, state.allocator)] = strings.clone(change.text, state.allocator)

      diagnostics := diagnostics_for_file(change.text)
      notification := PublishDiagnosticsNotification {
        jsonrpc = "2.0",
        method = "textDocument/publishDiagnostics",
        params = {
          uri = request.params.textDocument.uri,
          diagnostics = diagnostics,
        }
      }
      write_message(w, notification, context.temp_allocator)
    }

  case "textDocument/hover":
    request: HoverRequest
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    response := state_hover(state, request, context.temp_allocator)
    write_message(w, response, context.temp_allocator)

  case "textDocument/definition":
    request: DefinitionRequest
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    response := state_definition(state, request, context.temp_allocator)
    write_message(w, response, context.temp_allocator)

  case "textDocument/codeAction":
    request: CodeActionRequest
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    response := state_code_action(state, request, context.temp_allocator)
    write_message(w, response, context.temp_allocator)

  case "textDocument/completion":
    request: CompletionRequest
    err := json.unmarshal(contents, &request)
    assert(err == nil)

    response := state_completion(state, request, context.temp_allocator)
    write_message(w, response, context.temp_allocator)

  case:
    log.warn("UNHANDLED")
  }
}

ExampleStruct :: struct {
  testing: bool,
}

diagnostics_for_file :: proc(text: string, allocator := context.allocator) -> []Diagnostic {
  text := text
  diagnostics: [dynamic]Diagnostic

  row: uint = 0
  for line in strings.split_lines_iterator(&text) {
    defer row += 1

    bad_idx := strings.index(line, BAD_WORD)
    if bad_idx >= 0 {
      diagnostic := Diagnostic {
        range = { 
          start = { row, cast(uint)bad_idx }, 
          end = { row, cast(uint)bad_idx + len(BAD_WORD) } 
        },
        severity = .Error,
        source = "Common Sense",
        message = "Please make sure we use good language"
      }
      append(&diagnostics, diagnostic)
    }

    good_idx := strings.index(line, GOOD_WORD)
    if good_idx >= 0 {
      diagnostic := Diagnostic {
        range = { 
          start = { row, cast(uint)good_idx }, 
          end = { row, cast(uint)good_idx + len(GOOD_WORD) } 
        },
        severity = .Hint,
        source = "Common Sense",
        message = "Great choice :)"
      }
      append(&diagnostics, diagnostic)
    }
  }

  return diagnostics[:]
}

// @(test)
// test_encode_message :: proc(t: ^testing.T) {
//   expected := "Content-Length: 16\r\n\r\n{\"testing\":true}"
//   actual := encode_message(ExampleStruct{testing = true}, context.temp_allocator)
//   testing.expect_value(t, actual, expected)
// }

@(test)
test_decode_message :: proc(t: ^testing.T) {
//   // expected := ExampleStruct { testing = true }
  message := "Content-Length: 15\r\n\r\n{\"method\":\"initialize\"}"
  method, content := decode_message(transmute([]byte)message, context.temp_allocator)
  testing.expect_value(t, len(content), 15)
  testing.expect_value(t, method, "initialize")
}

// maybe use writers instead
// maybe use vec write to get around coppying the buf
// encode_message :: proc(msg: any, allocator := context.allocator) -> string {
//   context.allocator = allocator
//   content, err := json.marshal(msg)
//   if err != nil {
//     log.fatal(err)
//   }
//   return fmt.aprintf("Content-Length: %d\r\n\r\n%s", len(content), content)
// }

write_message :: proc(w: io.Writer, msg: any, allocator := context.allocator) {
  // io.write(w, msg)
  // fmt.wprintf("Content-Length: %d\r\n\r\n%s", len(content), content)


  context.allocator = allocator
  content, err := json.marshal(msg)
  if err != nil {
    log.fatal(err)
  }
  // return fmt.aprintf("Content-Length: %d\r\n\r\n%s", len(content), content)
  fmt.wprintf(w, "Content-Length: %d\r\n\r\n%s", len(content), content)
}

header_separator_str := "\r\n\r\n"
header_separator := transmute([]byte)header_separator_str

// handle erros
// we could case insesitivly search for content-length
// and use to allocate the amount need for the read
decode_message :: proc(msg: []byte, allocator := context.allocator) -> (method: string, content: []byte) {
  context.allocator = allocator
  msg := msg

  headers, headers_ok := bytes.split_iterator(&msg, header_separator)
  body, body_ok := bytes.split_iterator(&msg, header_separator)

  content_length_str := cast(string)headers[len("Content-Length: "):]
  content_length, content_length_ok := strconv.parse_int(content_length_str)
  assert(content_length_ok)

  base_message: struct { method: string }
  log.assert(len(body) >= content_length)
  err := json.unmarshal(body[:content_length], &base_message)
  if err != nil do log.warn(err)
  // log.assert(err == nil)

  return base_message.method, body[:content_length]
}
