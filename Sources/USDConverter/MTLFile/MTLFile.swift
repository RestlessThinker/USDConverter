//
//  MTLFile.swift
//  USDConverter
//
//  Created by Emma Alyx Wunder on 10.12.19.
//  Copyright © 2019 Emma Alyx Wunder. All rights reserved.
//

import Foundation

class MTLFile {

	let file: URL
	var materials: [MTLMaterial]

	init(mtlFile: URL) throws {
		self.file = mtlFile
		self.materials = []
		
	}

}
