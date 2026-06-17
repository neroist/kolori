package kolori

import "core:log"
import "core:mem"

logging_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	result: []byte,
	err: mem.Allocator_Error,
) 
{
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		log.debugf(
			"Allocation made of size %i and alignment %i",
			size,
			alignment,
			location = loc,
		)
	case .Free:
		log.debugf(
			"Free made of size %i",
			size,
			location = loc,
		)
	case .Free_All:
		log.debugf(
			"Freed all memory allocated",
			location = loc,
		)
	case .Resize, .Resize_Non_Zeroed:
		log.debugf(
			"Resize made from size %i to size %i with alignment %i",
			old_size,
			size,
			alignment,
			location = loc,
		)
	}

	return mem.tracking_allocator_proc(
		allocator_data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

@(require_results, no_sanitize_address)
logging_allocator :: proc(data: ^mem.Tracking_Allocator) -> mem.Allocator {
	return mem.Allocator{
		data = data,
		procedure = logging_allocator_proc,
	}
}
