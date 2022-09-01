const std = @import("std");
const io = std.io;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const BoundedArray = std.BoundedArray;
const msg = @import("msg.zig");
const Extension = @import("extension.zig").Extension;
const SignatureAlgorithm = @import("signatures.zig").SignatureAlgorithm;
const x509 = @import("x509.zig");

pub const Certificate = struct {
    const MAX_CERT_REQ_CTX_LENGTH = 256;
    cert_req_ctx: BoundedArray(u8, MAX_CERT_REQ_CTX_LENGTH) = undefined,
    cert_list: ArrayList(CertificateEntry) = undefined,

    const Self = @This();

    pub fn init(ctx_len: usize, allocator: std.mem.Allocator) !Self {
        return Self{
            .cert_req_ctx = try BoundedArray(u8, MAX_CERT_REQ_CTX_LENGTH).init(ctx_len),
            .cert_list = ArrayList(CertificateEntry).init(allocator),
        };
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Self {
        const ctx_len = try reader.readIntBig(u16);
        var res = try Self.init(ctx_len, allocator);

        _ = try reader.readAll(res.cert_req_ctx.slice());
        const cert_len = try reader.readIntBig(u16);
        var i: usize = 0;
        while (i < cert_len) {
            const cert = try CertificateEntry.decode(reader, allocator);
            try res.cert_list.append(cert);
            i += cert.length();
        }

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += @sizeOf(u16); // certificate length
        len += self.cert_req_ctx.len;

        len += @sizeOf(u16); // cert list length
        for (self.cert_list.items) |c| {
            len += c.length();
        }

        return len;
    }

    pub fn deinit(self: Self) void {
        for (self.cert_list.items) |e| {
            e.deinit();
        }
        self.cert_list.deinit();
    }
};

pub const CertificateEntry = struct {
    cert: x509.Certificate = undefined,
    cert_len: usize = 0, // TODO: remove this
    extensions: ArrayList(Extension) = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .extensions = ArrayList(Extension).init(allocator),
        };
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Self {
        var res = Self.init(allocator);
        const cert_type = try reader.readIntBig(u8); // CertificateType
        assert(cert_type == 0); // only X.509 certificate is accepted.
        const cert_len = try reader.readIntBig(u16);

        res.cert_len = cert_len;
        res.cert = try x509.Certificate.decode(reader, allocator);

        try msg.decodeExtensions(reader, allocator, &res.extensions, .server_hello, false);

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;
        len += 1; // CertificateType

        len += @sizeOf(u16); // cert_data length
        len += self.cert_len;

        len += @sizeOf(u16); // extension length
        for (self.extensions.items) |e| {
            len += e.length();
        }

        return len;
    }

    pub fn deinit(self: Self) void {
        self.cert.deinit();
        for (self.extensions.items) |e| {
            e.deinit();
        }
        self.extensions.deinit();
    }
};

pub const CertificateVerify = struct {
    algorithm: SignatureAlgorithm = undefined,
    signature: ArrayList(u8) = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .signature = ArrayList(u8).init(allocator),
        };
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Self {
        var res = Self.init(allocator);

        res.algorithm = @intToEnum(SignatureAlgorithm, try reader.readIntBig(u16));
        const sig_len = try reader.readIntBig(u16);
        var i: u16 = 0;
        while (i < sig_len) : (i += 1) {
            try res.signature.append(try reader.readIntBig(u8));
        }

        return res;
    }

    pub fn length(self: Self) usize {
        var len: usize = 0;

        len += @sizeOf(SignatureAlgorithm); // signature algorithm
        len += @sizeOf(u16); // signature length
        len += self.signature.items.len;

        return len;
    }

    pub fn deinit(self: Self) void {
        self.signature.deinit();
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Certificate decode" {
    const recv_data = [_]u8{ 0x0B, 0x00, 0x01, 0xB9, 0x00, 0x00, 0x01, 0xB5, 0x00, 0x01, 0xB0, 0x30, 0x82, 0x01, 0xAC, 0x30, 0x82, 0x01, 0x15, 0xA0, 0x03, 0x02, 0x01, 0x02, 0x02, 0x01, 0x02, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00, 0x30, 0x0E, 0x31, 0x0C, 0x30, 0x0A, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x03, 0x72, 0x73, 0x61, 0x30, 0x1E, 0x17, 0x0D, 0x31, 0x36, 0x30, 0x37, 0x33, 0x30, 0x30, 0x31, 0x32, 0x33, 0x35, 0x39, 0x5A, 0x17, 0x0D, 0x32, 0x36, 0x30, 0x37, 0x33, 0x30, 0x30, 0x31, 0x32, 0x33, 0x35, 0x39, 0x5A, 0x30, 0x0E, 0x31, 0x0C, 0x30, 0x0A, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x03, 0x72, 0x73, 0x61, 0x30, 0x81, 0x9F, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x81, 0x8D, 0x00, 0x30, 0x81, 0x89, 0x02, 0x81, 0x81, 0x00, 0xB4, 0xBB, 0x49, 0x8F, 0x82, 0x79, 0x30, 0x3D, 0x98, 0x08, 0x36, 0x39, 0x9B, 0x36, 0xC6, 0x98, 0x8C, 0x0C, 0x68, 0xDE, 0x55, 0xE1, 0xBD, 0xB8, 0x26, 0xD3, 0x90, 0x1A, 0x24, 0x61, 0xEA, 0xFD, 0x2D, 0xE4, 0x9A, 0x91, 0xD0, 0x15, 0xAB, 0xBC, 0x9A, 0x95, 0x13, 0x7A, 0xCE, 0x6C, 0x1A, 0xF1, 0x9E, 0xAA, 0x6A, 0xF9, 0x8C, 0x7C, 0xED, 0x43, 0x12, 0x09, 0x98, 0xE1, 0x87, 0xA8, 0x0E, 0xE0, 0xCC, 0xB0, 0x52, 0x4B, 0x1B, 0x01, 0x8C, 0x3E, 0x0B, 0x63, 0x26, 0x4D, 0x44, 0x9A, 0x6D, 0x38, 0xE2, 0x2A, 0x5F, 0xDA, 0x43, 0x08, 0x46, 0x74, 0x80, 0x30, 0x53, 0x0E, 0xF0, 0x46, 0x1C, 0x8C, 0xA9, 0xD9, 0xEF, 0xBF, 0xAE, 0x8E, 0xA6, 0xD1, 0xD0, 0x3E, 0x2B, 0xD1, 0x93, 0xEF, 0xF0, 0xAB, 0x9A, 0x80, 0x02, 0xC4, 0x74, 0x28, 0xA6, 0xD3, 0x5A, 0x8D, 0x88, 0xD7, 0x9F, 0x7F, 0x1E, 0x3F, 0x02, 0x03, 0x01, 0x00, 0x01, 0xA3, 0x1A, 0x30, 0x18, 0x30, 0x09, 0x06, 0x03, 0x55, 0x1D, 0x13, 0x04, 0x02, 0x30, 0x00, 0x30, 0x0B, 0x06, 0x03, 0x55, 0x1D, 0x0F, 0x04, 0x04, 0x03, 0x02, 0x05, 0xA0, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00, 0x03, 0x81, 0x81, 0x00, 0x85, 0xAA, 0xD2, 0xA0, 0xE5, 0xB9, 0x27, 0x6B, 0x90, 0x8C, 0x65, 0xF7, 0x3A, 0x72, 0x67, 0x17, 0x06, 0x18, 0xA5, 0x4C, 0x5F, 0x8A, 0x7B, 0x33, 0x7D, 0x2D, 0xF7, 0xA5, 0x94, 0x36, 0x54, 0x17, 0xF2, 0xEA, 0xE8, 0xF8, 0xA5, 0x8C, 0x8F, 0x81, 0x72, 0xF9, 0x31, 0x9C, 0xF3, 0x6B, 0x7F, 0xD6, 0xC5, 0x5B, 0x80, 0xF2, 0x1A, 0x03, 0x01, 0x51, 0x56, 0x72, 0x60, 0x96, 0xFD, 0x33, 0x5E, 0x5E, 0x67, 0xF2, 0xDB, 0xF1, 0x02, 0x70, 0x2E, 0x60, 0x8C, 0xCA, 0xE6, 0xBE, 0xC1, 0xFC, 0x63, 0xA4, 0x2A, 0x99, 0xBE, 0x5C, 0x3E, 0xB7, 0x10, 0x7C, 0x3C, 0x54, 0xE9, 0xB9, 0xEB, 0x2B, 0xD5, 0x20, 0x3B, 0x1C, 0x3B, 0x84, 0xE0, 0xA8, 0xB2, 0xF7, 0x59, 0x40, 0x9B, 0xA3, 0xEA, 0xC9, 0xD9, 0x1D, 0x40, 0x2D, 0xCC, 0x0C, 0xC8, 0xF8, 0x96, 0x12, 0x29, 0xAC, 0x91, 0x87, 0xB4, 0x2B, 0x4D, 0xE1, 0x00, 0x00 };
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try msg.Handshake.decode(readStream.reader(), std.testing.allocator, null);
    defer res.deinit();

    // check all data was read.
    try expectError(error.EndOfStream, readStream.reader().readByte());

    try expect(res == .certificate);
    const cert = res.certificate;

    try expect(cert.cert_req_ctx.len == 0);
    try expect(cert.cert_list.items.len == 1);
    try expect(cert.cert_list.items[0].cert_data.items.len == 432);
    try expect(cert.cert_list.items[0].extensions.items.len == 0);
}

test "CertificateVerify decode" {
    const recv_data = [_]u8{ 0x0F, 0x00, 0x00, 0x84, 0x08, 0x04, 0x00, 0x80, 0x5A, 0x74, 0x7C, 0x5D, 0x88, 0xFA, 0x9B, 0xD2, 0xE5, 0x5A, 0xB0, 0x85, 0xA6, 0x10, 0x15, 0xB7, 0x21, 0x1F, 0x82, 0x4C, 0xD4, 0x84, 0x14, 0x5A, 0xB3, 0xFF, 0x52, 0xF1, 0xFD, 0xA8, 0x47, 0x7B, 0x0B, 0x7A, 0xBC, 0x90, 0xDB, 0x78, 0xE2, 0xD3, 0x3A, 0x5C, 0x14, 0x1A, 0x07, 0x86, 0x53, 0xFA, 0x6B, 0xEF, 0x78, 0x0C, 0x5E, 0xA2, 0x48, 0xEE, 0xAA, 0xA7, 0x85, 0xC4, 0xF3, 0x94, 0xCA, 0xB6, 0xD3, 0x0B, 0xBE, 0x8D, 0x48, 0x59, 0xEE, 0x51, 0x1F, 0x60, 0x29, 0x57, 0xB1, 0x54, 0x11, 0xAC, 0x02, 0x76, 0x71, 0x45, 0x9E, 0x46, 0x44, 0x5C, 0x9E, 0xA5, 0x8C, 0x18, 0x1E, 0x81, 0x8E, 0x95, 0xB8, 0xC3, 0xFB, 0x0B, 0xF3, 0x27, 0x84, 0x09, 0xD3, 0xBE, 0x15, 0x2A, 0x3D, 0xA5, 0x04, 0x3E, 0x06, 0x3D, 0xDA, 0x65, 0xCD, 0xF5, 0xAE, 0xA2, 0x0D, 0x53, 0xDF, 0xAC, 0xD4, 0x2F, 0x74, 0xF3 };
    var readStream = io.fixedBufferStream(&recv_data);

    const res = try msg.Handshake.decode(readStream.reader(), std.testing.allocator, null);
    defer res.deinit();

    // check all data was read.
    try expectError(error.EndOfStream, readStream.reader().readByte());

    try expect(res == .certificate_verify);
}
