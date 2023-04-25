//
//  Descriptor.swift
//  KakaJSON
//
//  Created by MJ Lee on 2019/7/31.
//  Copyright © 2019 MJ Lee. All rights reserved.
//

/// Must be struct, do not use class
/// Descriptor for layout
protocol Descriptor {}

// MARK: - NominalDescriptor
protocol NominalDescriptor: Descriptor {
    /// Flags describing the context, including its kind and format version
    var flags: ContextDescriptorFlags { get }
    
    /// The parent context, or null if this is a top-level context.
    var parent: RelativeContextPointer { get }
    
    /// The name of the type
    var name: RelativeDirectPointer<CChar> { get set }
    
    /// A pointer to the metadata access function for this type
    var accessFunctionPtr: RelativeDirectPointer<MetadataResponse> { get }
    
    /// A pointer to the field descriptor for the type, if any
    var fields: RelativeDirectPointer<FieldDescriptor> { get set }
    
    associatedtype OffsetType: BinaryInteger
    var fieldOffsetVectorOffset: FieldOffsetPointer<OffsetType> { get }
    
    /// generic info
    var genericContextHeader: TargetTypeGenericContextDescriptorHeader { get }
}

extension NominalDescriptor {
    var isGeneric: Bool { return (flags.value & 0x80) != 0 }
    var genericTypesCount: Int { return Int(genericContextHeader.base.numberOfParams) }
}

// MARK: - ModelDescriptor
protocol ModelDescriptor: NominalDescriptor {
    var numFields: UInt32 { get }
    mutating func fieldOffsets(_ type: Any.Type) -> [Int]
}

extension ModelDescriptor {
    mutating func fieldOffsets(_ type: Any.Type) -> [Int] {
        let ptr = ((type ~>> UnsafePointer<Int>.self) + Int(fieldOffsetVectorOffset.offset))
            .kj_raw ~> OffsetType.self
        return (0..<Int(numFields)).map { Int(ptr[$0]) }
    }
}

extension ClassDescriptor {
    mutating func fieldOffsets(_ type: Any.Type) -> [Int] {
        var offset = 0
        if hasResilientSuperclass() {
            offset = Int(resilientMetadataBounds.advanced().pointee.immediateMembersOffset / MemoryLayout<Int>.size)
        } else {
            offset = Int(fieldOffsetVectorOffset.offset)
        }
        
        let ptr = ((type ~>> UnsafePointer<Int>.self) + offset)
            .kj_raw ~> OffsetType.self
        return (0..<Int(numFields)).map { Int(ptr[$0]) }
    }
}

public enum ContextDescriptorKind: Int {
    case module = 0
    case `extension` = 1
    case anonymous = 2
    case `protocol` = 3
    case opaqueType = 4
    case `class` = 16
    case `struct` = 17
    case `enum` = 18
}

// MARK: - Descriptor Inner Data Types
struct ContextDescriptorFlags {
    enum ContextDescriptorKind: UInt8 {
        case Module = 0         //表示一个模块
        case Extension          //表示一个扩展
        case Anonymous          //表示一个匿名的可能的泛型上下文，例如函数体
        case kProtocol          //表示一个协议
        case OpaqueType         //表示一个不透明的类型别名
        case Class = 16         //表示一个类
        case Struct             //表示一个结构体
        case Enum               //表示一个枚举
    }

    var value: UInt32

    /// The kind of context this descriptor describes.
    func getContextDescriptorKind() -> ContextDescriptorKind? {
        return ContextDescriptorKind.init(rawValue: numericCast(value & 0x1F))
    }

    /// Whether the context being described is generic.
    func isGeneric() -> Bool {
        return (value & 0x80) != 0
    }

    /// Whether this is a unique record describing the referenced context.
    func isUnique() -> Bool {
        return (value & 0x40) != 0
    }

    /// The format version of the descriptor. Higher version numbers may have
    /// additional fields that aren't present in older versions.
    func getVersion() -> UInt8 {
        return numericCast((value >> 8) & 0xFF)
    }

    /// The most significant two bytes of the flags word, which can have
    /// kind-specific meaning.
    func getKindSpecificFlags() -> UInt16 {
        return numericCast((value >> 16) & 0xFFFF)
    }
}

struct RelativeContextPointer {
    let offset: Int32
}

struct RelativeDirectPointer <Pointee> {
    var relativeOffset: Int32
    
    mutating func advanced() -> UnsafeMutablePointer<Pointee> {
        let offset = relativeOffset
        return withUnsafeMutablePointer(to: &self) {
            ($0.kj_raw + Int(offset)) ~> Pointee.self
        }
    }
}

//这个类型是通过当前地址的偏移值获得真正的地址，有点像文件目录，用当前路径的相对路径获得绝对路径。
struct RelativeDirectPointerA<T> {
    var offset: Int32 //存放的与当前地址的偏移值

    //通过地址的相对偏移值获得真正的地址
    mutating func get() -> UnsafeMutablePointer<T> {
        let offset = self.offset
        return withUnsafeMutablePointer(to: &self) {
            return UnsafeMutableRawPointer($0).advanced(by: numericCast(offset)).assumingMemoryBound(to: T.self)
        }
    }
}


struct FieldOffsetPointer <Pointee: BinaryInteger> {
    let offset: UInt32
}

struct MetadataResponse {}

struct TargetTypeGenericContextDescriptorHeader {
    var instantiationCache: Int32
    var defaultInstantiationPattern: Int32
    var base: TargetGenericContextDescriptorHeader
}

struct TargetGenericContextDescriptorHeader {
    var numberOfParams: UInt16
    var numberOfRequirements: UInt16
    var numberOfKeyArguments: UInt16
    var numberOfExtraArguments: UInt16
}
