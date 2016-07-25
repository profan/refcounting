module refcounting.pointers;

import std.experimental.allocator : make, dispose, theAllocator, IAllocator;
import std.algorithm.mutation : move;
import std.typecons : Proxy;

template TypeRef(T) {

	static if (is (T == class)) {
		alias TypeRef  = T;
	} else {
		alias TypeRef = T*;
	}

} // TypeRef

mixin template GetRef(T, alias ptr) {

	static if (is (T == class)) {
		@property @safe ref T get() {
			return ptr;
		}
	} else {
		@property @safe ref T get() {
			return *ptr;
		}
	}

} // GetRef

private struct Data(T) {

	alias Type = TypeRef!T;

	// save this here
	IAllocator allocator;

	Type object;
	uint ref_count;
	uint weak_count;

	alias object this;

} // Data

struct SharedPtr(T) {

	private {
		Data!(T)* data_;
	}
	
	mixin GetRef!(data_.Type, data_);
	mixin Proxy!get;

	// no default construction
	@disable this();

	this(Args...)(Args args) {
		data_ = theAllocator.make!(Data!T)();
		data_.allocator = theAllocator;
		data_.object = data_.allocator.make!T(args);
		data_.ref_count = 1;
		data_.weak_count = 0;
	} // this

	this(this) {
		data_ = data_;
		data_.ref_count += 1;
	} // this(this)

	~this() {
		data_.ref_count -= 1;
		if (data_.ref_count == 0) {
			data_.allocator.dispose(data_.object);
			data_.object = null; // set this here to make sure violent crash on trying to dereference
			if (data_.weak_count == 0) {
				data_.allocator.dispose(data_);
			}
		}
	} // ~this

	auto weak() {
		return WeakPtr!(typeof(this))(this);
	} // weak

} // SharedPtr

version(unittest) {

	import std.stdio;

}

unittest {

	int thing = 0;

	struct SomeThing {

		int* thing_ptr;

		this(int* ptr_to_thing) {
			thing_ptr = ptr_to_thing;
			writefln("Created SomeThing!");
		} // this

		~this() {
			writefln("Destroyed SomeThing!");
			*thing_ptr = 10;
		} // ~this

	} // SomeThing

	{ auto shared_ptr = make_shared!SomeThing(&thing); } assert(thing == 10);

}

struct WeakPtr(SharedPtrType) {

	private {
		typeof(SharedPtrType.data_) data_;
	}
	
	mixin GetRef!(typeof(data_.object), data_);

	// no default construicton
	@disable this();
	@disable this(this);

	this(ref SharedPtrType ptr) {
		data_ = ptr.data_;
		data_.weak_count += 1;
	} // this

	~this() {
		data_.weak_count -= 1;
		if (data_.ref_count == 0 && data_.weak_count == 0) {
			data_.allocator.dispose(data_);
		}
	} // ~this

	bool opCast(CT : bool)() {
		return data_.ref_count != 0;
	} // opCast

} // WeakPtr

unittest {

	auto returnExpiredWeakPtr() {
		auto shared_ptr = make_shared!int(10);
		return shared_ptr.weak();
	}

	{
		auto weak_ptr = returnExpiredWeakPtr();
		assert(!weak_ptr);
	}

}

struct UniquePtr(T) {

	alias Type = TypeRef!T;
	mixin GetRef!(T, data_);
	mixin Proxy!get;

	private {

		IAllocator allocator_;
		Type data_;

	}

	// no default construction
	@disable this();
	@disable this(this);

	private this(Type data) {
		data_ = data;
	} // this

	this(Args...)(Args args) {
		allocator_ = theAllocator;
		data_ = allocator_.make!T(args);
	} // this

	~this() {
		if (data_) {
			allocator_.dispose(data_);
		}
	} // ~this

	auto release() {
		return move(this);
	} // release

} // UniquePtr

unittest {

	auto getUniqueDouble(double v) {
		auto unique_thing = make_unique!double(v);
		return unique_thing.release();
	} // getUniqueDouble

	auto unique_double = getUniqueDouble(25);
	assert(unique_double.get == 25);

}

auto make_shared(T, Args...)(Args args) {
	return SharedPtr!T(args);
} // make_shared

auto make_unique(T, Args...)(Args args) {
	return UniquePtr!T(args);
} // make_unique
