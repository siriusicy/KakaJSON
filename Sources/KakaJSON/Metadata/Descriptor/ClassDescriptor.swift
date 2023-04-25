//
//  ClassDescriptor.swift
//  KakaJSON
//
//  Created by MJ Lee on 2019/7/31.
//  Copyright © 2019 MJ Lee. All rights reserved.
//

public enum MetadataInitializationKind: UInt16 {
  case none = 0
  case singleton = 1
  case foreign = 2
}

/// The type of reference this is to some type.
public enum TypeReferenceKind: UInt16 {
  /// This is a direct relative reference to the type's context descriptor.
  case directTypeDescriptor = 0x0
  
  /// This is an indirect relative reference to the type's context descriptor.
  case indirectTypeDescriptor = 0x1
  
  /// This is a direct relative reference to some Objective-C class metadata.
  case directObjCClass = 0x2
  
  /// This is an indirect relative reference to some Objective-C class metadata.
  case indirectObjCClass = 0x3
}

protocol FlagSet {
    associatedtype IntType : FixedWidthInteger
    var bits: IntType { get set }
    
    func lowMaskFor(_ BitWidth: Int) -> IntType
    
    func maskFor(_ FirstBit: Int) -> IntType
    
    func getFlag(_ Bit: Int) -> Bool
    
    func getField(_ FirstBit: Int, _ BitWidth: Int) -> IntType
}

extension FlagSet {
    func lowMaskFor(_ BitWidth: Int) -> IntType {
        return IntType((1 << BitWidth) - 1)
    }
    
    func maskFor(_ FirstBit: Int) -> IntType {
        return lowMaskFor(1) << FirstBit
    }
    
    func getFlag(_ Bit: Int) -> Bool {
        return ((bits & maskFor(Bit)) != 0)
    }
    
    func getField(_ FirstBit: Int, _ BitWidth: Int) -> IntType {
        return IntType((bits >> FirstBit) & lowMaskFor(BitWidth));
    }
}



/// The flags which describe a type's context descriptor.
struct TypeContextDescriptorFlags: FlagSet {
    
    typealias IntType = UInt16
    var bits: IntType
    
    // All of these values are bit offsets or widths.
    // Generic flags build upwards from 0.
    // Type-specific flags build downwards from 15.
    enum Specialization: Int {
        // Whether there's something unusual about how the metadata is initialized.
        // Meaningful for all type-descriptor kinds.
        case MetadataInitialization = 0
        // 这里枚举值2表示两个意思，还有一个是HasImportInfo，下面是HasImportInfo的释意
        // Set if the type has extended import information.
        // If true, a sequence of strings follow the null terminator in the descriptor, terminated by an empty string (i.e. by two null terminators in a row).  See TypeImportInfo for the details of these strings and the order in which they appear.
        case MetadataInitialization_width = 2 //HasImportInfo
        
        // The kind of reference that this class makes to its resilient superclass descriptor.  A TypeReferenceKind.
        // Only meaningful for class descriptors.
        case Class_ResilientSuperclassReferenceKind = 9
        case Class_ResilientSuperclassReferenceKind_width = 3
        
        // Whether the immediate class members in this metadata are allocated at negative offsets.  For now, we don't use this.
        case Class_AreImmediateMembersNegative = 12
        
        // Set if the context descriptor is for a class with resilient ancestry.
        // Only meaningful for class descriptors.
        case Class_HasResilientSuperclass = 13
        
        // Set if the context descriptor includes metadata for dynamically installing method overrides at metadata instantiation time.
        case Class_HasOverrideTable = 14
        
        // Set if the context descriptor includes metadata for dynamically constructing a class's vtables at metadata instantiation time.
        // Only meaningful for class descriptors.
        case Class_HasVTable = 15
    }
    
    enum MetadataInitializationKind: Int {
        // There are either no special rules for initializing the metadata or the metadata is generic.  (Genericity is set in the non-kind-specific descriptor flags.)
        case NoMetadataInitialization = 0
        // The type requires non-trivial singleton initialization using the "in-place" code pattern.
        case SingletonMetadataInitialization = 1
        
        // The type requires non-trivial singleton initialization using the "foreign" code pattern.
        case ForeignMetadataInitialization = 2
    }
    
}

/// Bounds for metadata objects.
struct TargetMetadataBounds {
  /// The negative extent of the metadata, in words.
    var negativeSizeInWords: UInt32
    
  /// The positive extent of the metadata, in words.
    var positiveSizeInWords: UInt32

  /// Return the total size of the metadata in bytes, including both
  /// negatively- and positively-offset members.
    func getTotalSizeInBytes() -> UInt {
        return (UInt(negativeSizeInWords) + UInt(positiveSizeInWords)) * UInt(MemoryLayout<UnsafeRawPointer>.size)
    }

  /// Return the offset of the address point of the metadata from its
  /// start, in bytes.
    func getAddressPointInBytes() -> UInt {
        return UInt(negativeSizeInWords) * UInt(MemoryLayout<UnsafeRawPointer>.size)
    }
}

struct TargetStoredClassMetadataBounds {
    var immediateMembersOffset: Int
    var bounds: TargetMetadataBounds
}

struct ExtraClassDescriptorFlags: FlagSet {
    
    enum kType: Int {
        /// Set if the context descriptor includes a pointer to an Objective-C
        /// resilient class stub structure. See the description of
        /// TargetObjCResilientClassStubInfo in Metadata.h for details.
        ///
        /// Only meaningful for class descriptors when Objective-C interop is
        /// enabled.
        case HasObjCResilientClassStub = 0
    }
    
    typealias IntType = UInt32
    var bits: IntType
    
}


struct ClassDescriptor: ModelDescriptor {
    /// Flags describing the context, including its kind and format version
    let flags: ContextDescriptorFlags
    
    /// The parent context, or null if this is a top-level context.
    let parent: RelativeContextPointer
    
    /// The name of the type
    var name: RelativeDirectPointer<CChar>
    
    /// A pointer to the metadata access function for this type
    let accessFunctionPtr: RelativeDirectPointer<MetadataResponse>
    
    /// A pointer to the field descriptor for the type, if any
    var fields: RelativeDirectPointer<FieldDescriptor>
    
    /// The type of the superclass, expressed as a mangled type name that can refer to the generic arguments of the subclass type
    let superclassType: RelativeDirectPointer<CChar>
    
    var resilientMetadataBounds: RelativeDirectPointer<TargetStoredClassMetadataBounds>
    
    /// If this descriptor does not have a resilient superclass, this is the negative size of metadata objects of this class (in words)
    var metadataNegativeSizeInWords: UInt32 {
        get { UInt32(resilientMetadataBounds.relativeOffset) }
    }
    
    
    var extraClassFlags: ExtraClassDescriptorFlags
    /// If this descriptor does not have a resilient superclass, this is the positive size of metadata objects of this class (in words)
    var metadataPositiveSizeInWords: UInt32 {
        get { extraClassFlags.bits }
    }
    
    /// The number of additional members added by this class to the class metadata
    let numImmediateMembers: UInt32
    
    /// The number of stored properties in the class, not including its superclasses. If there is a field offset vector, this is its length.
    let numFields: UInt32
    
    /// The offset of the field offset vector for this class's stored properties in its metadata, in words. 0 means there is no field offset vector
    let fieldOffsetVectorOffset: FieldOffsetPointer<Int>
    
    
    let genericContextHeader: TargetTypeGenericContextDescriptorHeader
}



extension ClassDescriptor {
    
    func getTypeContextDescriptorFlags() -> TypeContextDescriptorFlags {
        return TypeContextDescriptorFlags.init(bits: flags.getKindSpecificFlags())
    }
    
    func hasResilientSuperclass() -> Bool {
        let Class_HasResilientSuperclass = TypeContextDescriptorFlags.Specialization.Class_HasResilientSuperclass.rawValue
        let result = getTypeContextDescriptorFlags().getFlag(Class_HasResilientSuperclass)
        return result
    }
}
