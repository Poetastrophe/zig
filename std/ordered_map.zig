// Ordered map
// Memory is owned by the callee (i.e. the data will live as long as the datastructure), but the caller supplies an allocator.
// Ordered set can be trivially implemented using Ordered map
// And have nice methods like lower bound and upper bound

const assert = std.debug.assert;
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const rb = std.rb;
const debug = std.debug;

pub fn OrderedMap(comptime K: type, comptime V: type, comptime compareFn: fn (a: K, b: K) mem.Compare) type {
    return struct {
        tree: rb.Tree,
        size: usize,
        allocator: *Allocator,

        const Self = @This();

        pub const KV = struct {
            key: K,
            value: V,
        };

        pub const NodeKVPair = struct {
            key_value: KV,
            node: rb.Node,
            pub fn init(data: KV) NodeKVPair {
                return NodeKVPair{
                    .key_value = data,
                    .node = undefined,
                };
            }
        };

        pub fn getSatelliteData(node: *rb.Node) *NodeKVPair {
            return @fieldParentPtr(NodeKVPair, "node", node);
        }

        fn internalCompareFn(a: *rb.Node, b: *rb.Node) mem.Compare {
            const keyA = getSatelliteData(anode).key_value.key;
            const keyB = getSatelliteData(bnode).key_value.key;
            return compareFn(keyA, keyB);
        }

        pub fn init(allocator: *Allocator) Self {
            var res = Self{
                .tree = undefined,
                .allocator = allocator,
                .size = 0,
            };
            res.tree.init(internalCompareFn);
            return res;
        }

        // Ignore deinit for now
        //
        // pub fn deinit(om: Self) void {
        //     deinitHelper(om, om.tree.root);
        // }

        // fn deinitHelper(om: Self, cur_node: ?*rb.Node) void {
        //     if (cur_node) |non_null_cur_node| {
        //         const child1 = non_null_cur_node.left;
        //         const child2 = non_null_cur_node.right;
        //         om.allocator.destroy(getSatelliteData(non_null_cur_node));
        //         deinitHelper(om, child1);
        //         deinitHelper(om, child2);
        //     } else {
        //         return;
        //     }
        // }

        pub fn clear(om: *Self) void {
            om.size = 0;
            om.deinitHelper(om.tree.root);
        }

        pub fn count(self: Self) usize {
            return self.size;
        }

        fn createNode(key_value: KV, allocator: *Allocator) !*NodeKVPair {
            var node = try allocator.create(NodeKVPair);
            node.* = NodeKVPair.init(key_value);
            return node;
        }

        /// get returns a key value pair matching the key, if found, otherwise null.
        pub fn get(om: *Self, key: K) ?*KV {
            var lookup_tuple = NodeKVPair.init(KV{ .key = key, .value = undefined });
            if (om.tree.lookup(&lookup_tuple.node)) |nodePtr| {
                return &getSatelliteData(nodePtr).key_value;
            }
            return null;
        }

        /// put returns the previous key value pair matching the key if it is in the tree (and it does clobber), otherwise it returns null.
        pub fn put(self: *Self, key: K, value: V) !?KV {
            var lookup_tuple = NodeKVPair.init(KV{ .key = key, .value = undefined });
            if (self.tree.lookup(&lookup_tuple.node)) |prev_entry| {
                var prev_parent_pointer: *NodeKVPair = getSatelliteData(prev_entry);
                var prev_kv: KV = prev_parent_pointer.key_value;
                prev_parent_pointer.key_value = KV{ .key = key, .value = value };
                return prev_kv;
            } else {
                var nodeTuple = try createNode(KV{ .key = key, .value = value }, self.allocator);
                var newNode = nodeTuple.node;
                _ = self.tree.insert(&newNode);
                return null;
            }
        }
    };
}

fn testCompareFn(a: u32, b: u32) mem.Compare {
    if (a < b) {
        return mem.Compare.LessThan;
    } else if (a == b) {
        return mem.Compare.Equal;
    } else if (a > b) {
        return mem.Compare.GreaterThan;
    }
    unreachable;
}

fn testGetNumber(node: *rb.Node) *testNumber {
    return @fieldParentPtr(testNumber, "node", node);
}

fn testManualCompareFn(l: *rb.Node, r: *rb.Node) mem.Compare {
    var left = testGetNumber(l);
    var right = testGetNumber(r);
    return testCompareFn(left.value, right.value);
}

fn testDumberCompareFn(l: *rb.Node, r: *rb.Node) mem.Compare {
    var left = testGetNumber(l);
    var right = testGetNumber(r);

    if (left.value < right.value) {
        return mem.Compare.LessThan;
    } else if (left.value == right.value) {
        return mem.Compare.Equal;
    } else if (left.value > right.value) {
        return mem.Compare.GreaterThan;
    }
    unreachable;
}

const testNumber = struct {
    node: rb.Node,
    value: u32,
};

test "Interface of rb outside rb" {
    var number: testNumber = undefined;
    number.value = 1000;
    var tree: rb.Tree = undefined;
    tree.init(testManualCompareFn);
    _ = tree.insert(&number.node);
    var dup: testNumber = undefined;
    dup.value = 1000;
    assert(tree.lookup(&dup.node) == &number.node);
    _ = tree.insert(&dup.node);
    assert(&dup.node != &number.node);
}

test "get" {
    const allocator = debug.global_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    const unpack = map.get(14);
}

test "put" {
    const allocator = debug.global_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    _ = try map.put(14, 1000);
}

test "Extracting KV from NodeKVPair" {
    const allocator = debug.global_allocator;
    const map = OrderedMap(u32, u32, testCompareFn);
    var someVar = map.NodeKVPair{ .key_value = map.KV{ .key = 42, .value = 1234 }, .node = undefined };
    assert(map.getSatelliteData(&someVar.node).key_value.key == 42);
    assert(map.getSatelliteData(&someVar.node).key_value.value == 1234);
}

test "Testing internal tree without all the clutter" {
    const allocator = std.heap.direct_allocator;
    const mapVals = OrderedMap(u32, u32, testCompareFn);
    var map = mapVals.init(allocator);
    var number = mapVals.NodeKVPair{ .key_value = mapVals.KV{ .key = 42, .value = 1234 }, .node = undefined };
    _ = map.tree.insert(&number.node);
    var dup = mapVals.NodeKVPair{ .key_value = mapVals.KV{ .key = 42, .value = 1234 }, .node = undefined };
    assert(map.tree.lookup(&dup.node) == &number.node);
    _ = map.tree.insert(&dup.node);
    assert(&dup.node != &number.node);
}

test "Test allocation" {
    const allocator = std.heap.direct_allocator;
    const mapVals = OrderedMap(u32, u32, testCompareFn);
    var node: *mapVals.NodeKVPair = undefined;
    {
        //Trash node when going out of scope
        var dup = mapVals.KV{ .key = 42, .value = 1234 };
        var extractNode: *mapVals.NodeKVPair = try mapVals.createNode(dup, allocator);
        node = extractNode;
    }
    assert(node.key_value.key == 42);
    assert(node.key_value.value == 1234);
    allocator.destroy(node);
}

//This fails
//Seems like it loses the associated data
test "put multiple values" {
    const allocator = std.heap.direct_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    const mapVals = OrderedMap(u32, u32, testCompareFn);
    const getNode = mapVals.getSatelliteData;

    _ = try map.put(14, 0);
    _ = try map.put(20, 1);
    _ = try map.put(100, 2);
    _ = try map.put(1234, 3);
}

//Value is NodeKVPair{ .key_value = KV{ .key = 2400459200, .value = 32766 }, .node = Node{ .left = null, .right = null, .parent_and_color = 0 } }
//Seems like {14, 0} is never inserted
test "Check if put actually puts anything" {
    const allocator = std.heap.direct_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    const mapVals = OrderedMap(u32, u32, testCompareFn);
    const getNode = mapVals.getSatelliteData;

    _ = try map.put(14, 0);
    var first = getNode(map.tree.first().?);
    std.debug.warn("Value is {} \n", first);
    assert(first.key_value.value == 0);
    // first = getNode(map.tree.first().?
    // assert(map.tree.first());
}

//Get somehow finds null. Even though it should find a node with key 14 value 1000
test "put and then get" {
    const allocator = std.heap.direct_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    const res = try map.put(14, 1000);
    assert(res == null);
    var someval = map.get(14).?;
    assert(someval.value == 1000);
}

test "Insert values and then clean them up" {
    const allocator = std.heap.direct_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    defer map.deinit();

    const mapVals = OrderedMap(u32, u32, testCompareFn);
    const getNode = mapVals.getSatelliteData;

    _ = try map.put(14, 0);
    _ = try map.put(20, 1);
    _ = try map.put(100, 2);
    _ = try map.put(1234, 3);
}

test "assert root is not null" {
    const allocator = std.heap.c_allocator;
    var map = OrderedMap(u32, u32, testCompareFn).init(allocator);
    defer map.deinit();

    const mapVals = OrderedMap(u32, u32, testCompareFn);
    const getNode = mapVals.getSatelliteData;

    _ = try map.put(14, 0);
    // _ = try map.put(20, 1);
    // _ = try map.put(100, 2);
    // _ = try map.put(1234, 3);
    assert(map.tree.root != null);
}
