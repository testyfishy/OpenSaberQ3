extends Node

signal request_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, token: int, user_data: Dictionary)

@export var max_simultaneous_request: int = 5
## 0 = no timeout (Godot's default). API calls should set a short one, downloads leave it at 0.
@export var request_timeout: float = 0.0
## Sent with every request; used for the descriptive User-Agent BeatSaver asks for.
@export var default_headers: PackedStringArray = PackedStringArray()

var _next_token := 0
var _request_queue := []
var _pending_requests_by_token := {}
# The bound callable is what was connected, and the only thing that can be disconnected again.
var _bound_callables := {}

func request(url: String, user_data: Dictionary={}) -> int:
	var token := _next_token
	_next_token = _next_token + 1
	
	if _pending_requests_by_token.size() >= max_simultaneous_request:
		# queue request for later
		_request_queue.push_back([url,user_data,token])
	else:
		# handle request now
		_request(url, user_data, token)
	
	return token
	
# internal method for creating a new request
func _request(url: String, user_data: Dictionary, token: int) -> void:
	var new_request := HTTPRequest.new()
	new_request.timeout = request_timeout
	add_child(new_request)
	var bound := _on_request_complete.bind(token, user_data)
	_bound_callables[token] = bound
	new_request.request_completed.connect(bound)
	var res := new_request.request(url, default_headers)
	if res == OK:
		_pending_requests_by_token[token] = new_request
	else:
		vr.log_error('failed to request url = "%s"' % url)
		if new_request.request_completed.is_connected(bound):
			new_request.request_completed.disconnect(bound)
		remove_child(new_request)
		_bound_callables.erase(token)
		_pending_requests_by_token.erase(token)
		# Still answer, deferred so the caller has returned from request() first: a caller that
		# waits for a completion (to free a slot, say) must never be left hanging.
		request_complete.emit.call_deferred(res, 0, PackedStringArray(), PackedByteArray(), token, user_data)
	
func cancel_request(token: int) -> void:
	if _pending_requests_by_token.has(token):
		@warning_ignore("unsafe_cast")
		var request: HTTPRequest = _pending_requests_by_token[token] as HTTPRequest
		var bound: Callable = _bound_callables.get(token, Callable())
		if bound.is_valid() and request.request_completed.is_connected(bound):
			request.request_completed.disconnect(bound)
		request.cancel_request()
		remove_child(request)
		_pending_requests_by_token.erase(token)
	_bound_callables.erase(token)
	# A request that has not started yet is only in the queue; make sure it never starts.
	for i in range(_request_queue.size() - 1, -1, -1):
		if int(_request_queue[i][2]) == token:
			_request_queue.remove_at(i)
	
func cancel_all() -> void:
	for token in _pending_requests_by_token.keys():
		self.cancel_request(token)
	_request_queue.clear()

func _on_request_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, token: int, user_data: Dictionary) -> void:
	# clean up request
	if _pending_requests_by_token.has(token):
		remove_child(_pending_requests_by_token[token])
		_pending_requests_by_token.erase(token)
	_bound_callables.erase(token)
	
	# initiate next queued request if there is one
	if ! _request_queue.is_empty():
		var request_args = _request_queue[0]
		_request_queue.pop_front()
		self.request(request_args[0],request_args[1])
		
	request_complete.emit(result, response_code, headers, body, token, user_data)
