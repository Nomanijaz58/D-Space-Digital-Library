<?php

namespace MediaWiki\Extension\FMCRepository;

use MediaWiki\Config\Config;
use MediaWiki\MediaWikiServices;
use MediaWiki\SpecialPage\SpecialPage;
use MediaWiki\Html\Html;

class SpecialFMCRepository extends SpecialPage {
	public function __construct() {
		parent::__construct( 'FMCRepository' );
	}

	public function execute( $subPage ) {
		$this->setHeaders();
		$out = $this->getOutput();
		$request = $this->getRequest();

		$q = trim( (string)$request->getVal( 'q', '' ) );
		$size = (int)$request->getVal( 'size', 20 );
		if ( $size <= 0 || $size > 100 ) {
			$size = 20;
		}

		$out->addHTML( $this->buildSearchForm( $q, $size ) );

		if ( $q === '' ) {
			return;
		}

		try {
			$results = $this->searchAdapter( $q, $size );
			$out->addHTML( $this->renderResults( $q, $results ) );
		} catch ( \Exception $e ) {
			$out->addHTML( Html::rawElement( 'div', [ 'class' => 'error' ], $this->msg( 'fmcrepo-error-api' )->escaped() ) );
		}
	}

	private function buildSearchForm( string $q, int $size ): string {
		$form = Html::openElement( 'form', [
			'method' => 'get',
			'action' => $this->getPageTitle()->getLocalURL(),
		] );

		$form .= Html::element( 'input', [
			'type' => 'text',
			'name' => 'q',
			'value' => $q,
			'placeholder' => $this->msg( 'fmcrepo-search-placeholder' )->text(),
			'style' => 'min-width: 320px; padding: 6px;'
		] );

		$form .= ' ';

		$form .= Html::element( 'input', [
			'type' => 'number',
			'name' => 'size',
			'value' => (string)$size,
			'min' => '1',
			'max' => '100',
			'style' => 'width: 80px; padding: 6px;'
		] );

		$form .= ' ';

		$form .= Html::element( 'button', [
			'type' => 'submit',
			'style' => 'padding: 6px 10px;'
		], $this->msg( 'fmcrepo-search-button' )->text() );

		$form .= Html::closeElement( 'form' );

		return $form;
	}

	private function searchAdapter( string $q, int $size ): array {
		/** @var Config $config */
		$config = MediaWikiServices::getInstance()->getConfigFactory()->makeConfig( 'main' );
		$baseUrl = rtrim( (string)$config->get( 'FMCRepositoryAPIUrl' ), '/' );

		$url = $baseUrl . '/search?query=' . rawurlencode( $q ) . '&size=' . (int)$size;

		$factory = MediaWikiServices::getInstance()->getHttpRequestFactory();
		$resp = $factory->get( $url, [
			'timeout' => 15,
			'headers' => [ 'Accept' => 'application/json' ],
		], __METHOD__ );

		$data = json_decode( $resp, true );
		if ( !is_array( $data ) ) {
			throw new \RuntimeException( 'Invalid JSON from adapter' );
		}
		return $data;
	}

	private function renderResults( string $q, array $data ): string {
		$objs = $data['_embedded']['searchResult']['_embedded']['objects'] ?? [];
		if ( !is_array( $objs ) || count( $objs ) === 0 ) {
			return Html::element( 'p', [], $this->msg( 'fmcrepo-no-results' )->text() );
		}

		$html = Html::element( 'h2', [], $this->msg( 'fmcrepo-results-title', $q )->text() );

		$rows = '';
		foreach ( $objs as $o ) {
			$io = $o['_embedded']['indexableObject'] ?? [];
			$title = is_array( $io ) ? (string)( $io['name'] ?? '' ) : '';
			$link = '';
			if ( is_array( $io ) ) {
				$link = (string)( $io['_links']['self']['href'] ?? '' );
			}

			$rows .= Html::rawElement( 'tr', [],
				Html::rawElement( 'td', [ 'style' => 'padding: 4px 8px;' ], htmlspecialchars( $title ) ) .
				Html::rawElement( 'td', [ 'style' => 'padding: 4px 8px;' ], $link ? Html::element( 'a', [ 'href' => $link, 'target' => '_blank', 'rel' => 'noopener' ], $this->msg( 'fmcrepo-item-link' )->text() ) : '' )
			);
		}

		$table = Html::rawElement( 'table', [
			'class' => 'wikitable',
			'style' => 'margin-top: 10px;'
		],
			Html::rawElement( 'tr', [],
				Html::element( 'th', [ 'style' => 'padding: 4px 8px;' ], $this->msg( 'fmcrepo-item-title' )->text() ) .
				Html::element( 'th', [ 'style' => 'padding: 4px 8px;' ], $this->msg( 'fmcrepo-item-link' )->text() )
			) .
			$rows
		);

		$html .= $table;
		return $html;
	}
}
